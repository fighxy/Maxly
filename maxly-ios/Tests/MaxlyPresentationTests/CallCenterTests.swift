import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Звонок без сети: состояние двигает тест.
@MainActor
final class FakeCallControl: CallControl {
    var state = CallState() {
        didSet { onChange?(state) }
    }
    var onChange: ((CallState) -> Void)?
    let connection: CallConnection
    let role: CallRole
    let isGroup: Bool
    var started = 0
    var accepted: [Bool] = []
    var hungUp = 0
    var muted: [Bool] = []
    var camera: [Bool] = []
    var cameraSwitches = 0
    var screen: [Bool] = []
    var speaker: [Bool] = []
    var recording: [Bool] = []
    var invited: [[String]] = []

    init(connection: CallConnection, role: CallRole, isGroup: Bool) {
        self.connection = connection
        self.role = role
        self.isGroup = isGroup
        state.phase = role == .callee ? .ringing : .connecting
    }

    func start() async { started += 1 }
    func accept(video: Bool) async {
        accepted.append(video)
        state.phase = .connecting
    }
    func hangUp() async {
        hungUp += 1
        if !state.isEnded {
            state.phase = .ended(role == .callee && accepted.isEmpty ? .rejected : .hungUp)
        }
    }
    func setMuted(_ muted: Bool) async {
        self.muted.append(muted)
        state.muted = muted
    }
    func setCamera(_ on: Bool) async {
        camera.append(on)
        state.cameraOn = on
    }
    func switchCamera() async { cameraSwitches += 1 }
    func setScreenSharing(_ on: Bool) async {
        screen.append(on)
        state.screenSharing = on
    }
    func setSpeaker(_ on: Bool) {
        speaker.append(on)
        state.speakerOn = on
    }
    func setRecording(_ on: Bool) async {
        recording.append(on)
        state.recording = on
    }
    func invite(userIds: [String]) async throws(MaxlyError) { invited.append(userIds) }

    func move(to phase: CallState.Phase, at date: Date? = nil) {
        var next = state
        next.phase = phase
        if phase == .active, next.activeSince == nil { next.activeSince = date ?? Date() }
        state = next
    }
}

@MainActor
final class FakeCallEngine: CallEngine {
    var calls: [FakeCallControl] = []
    var last: FakeCallControl? { calls.last }

    func makeCall(connection: CallConnection, role: CallRole, isGroup: Bool) -> any CallControl {
        let call = FakeCallControl(connection: connection, role: role, isGroup: isGroup)
        calls.append(call)
        return call
    }
}

final class FakeCallService: CallService, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<IncomingCall>
    private let continuation: AsyncStream<IncomingCall>.Continuation
    private var _started: [(String, Bool)] = []
    private var _joined: [String] = []
    var startError: MaxlyError?
    var startGate: Gate?
    var linkPreview: CallLinkPreview?

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: IncomingCall.self)
    }

    private var _rejected: [String] = []
    var rejectError: MaxlyError?
    var rejected: [String] { lock.withLock { _rejected } }
    var started: [(String, Bool)] { lock.withLock { _started } }
    var joined: [String] { lock.withLock { _joined } }

    func ring(_ call: IncomingCall) { continuation.yield(call) }

    func startCall(peerId: String, isVideo: Bool) async throws(MaxlyError) -> CallConnection {
        lock.withLock { _started.append((peerId, isVideo)) }
        if let startGate { await startGate.wait() }
        if let startError { throw startError }
        return CallConnection(conversationId: "out", signalingURL: URL(string: "wss://sig.test/out")!, selfId: 1, isVideo: isVideo)
    }

    func join(link: String, isVideo: Bool) async throws(MaxlyError) -> CallConnection {
        lock.withLock { _joined.append(link) }
        return CallConnection(
            conversationId: "group", signalingURL: URL(string: "wss://sig.test/group")!, selfId: 1,
            joinLink: URL(string: "https://max.ru/joincall/tok")
        )
    }

    func createLink() async throws(MaxlyError) -> CallLink {
        CallLink(url: URL(string: "https://max.ru/joincall/new")!, name: "Созвон")
    }

    func preview(link: String) async throws(MaxlyError) -> CallLinkPreview? { linkPreview }

    func incomingCalls() -> AsyncStream<IncomingCall> { stream }

    func reject(conversationId: String, peerId: String) async throws(MaxlyError) {
        lock.withLock { _rejected.append(conversationId) }
        if let rejectError { throw rejectError }
    }
}

/// CallKit без системы: действие сразу уходит делегату, как делает `CXProvider`.
@MainActor
final class FakeCallSystem: CallSystem {
    weak var delegate: (any CallSystemDelegate)?
    var incoming: [(UUID, String, String, Bool)] = []
    var requests: [CallSystemAction] = []
    var connecting: [UUID] = []
    var connected: [UUID] = []
    var ended: [(UUID, CallEndReason)] = []
    var updates: [(UUID, String)] = []
    var refuseRequests = false

    func reportIncoming(id: UUID, handle: String, name: String, video: Bool) async throws {
        incoming.append((id, handle, name, video))
    }

    func request(_ action: CallSystemAction) async throws {
        requests.append(action)
        if refuseRequests { throw CancellationError() }
        switch action {
        case .start: break
        case .answer(let id): delegate?.systemAnswered(id)
        case .end(let id): delegate?.systemEnded(id)
        case .mute(let id, let muted): delegate?.systemMuted(id, muted: muted)
        }
    }

    func reportConnecting(id: UUID) { connecting.append(id) }
    func reportConnected(id: UUID) { connected.append(id) }
    func reportEnded(id: UUID, reason: CallEndReason) { ended.append((id, reason)) }
    func reportUpdate(id: UUID, name: String, video: Bool) { updates.append((id, name)) }
}

@Suite("Центр звонков")
@MainActor
struct CallCenterTests {
    private let peer = CallCenter.Peer(id: "20", name: "Анна")

    private func incoming(_ id: String = "in-1", name: String = "Борис", video: Bool = false, expiresAt: Date? = nil) -> IncomingCall {
        IncomingCall(
            conversationId: id, callerId: "30", callerName: name, isVideo: video,
            connection: CallConnection(conversationId: id, signalingURL: URL(string: "wss://sig.test/in")!, selfId: 2, isVideo: video),
            expiresAt: expiresAt
        )
    }

    private func makeCenter(
        system: FakeCallSystem? = FakeCallSystem(),
        lookup: @escaping @Sendable (String) async -> CallCenter.Peer? = { _ in nil }
    ) -> (CallCenter, FakeCallService, FakeCallEngine, FakeCallSystem?) {
        let service = FakeCallService()
        let engine = FakeCallEngine()
        let center = CallCenter(service: service, engine: engine, system: system, lookup: lookup, endedDisplay: .milliseconds(300))
        center.activate()
        return (center, service, engine, system)
    }

    @Test("Исходящий: сервер, звонок через систему, гудки, разговор, сброс")
    func outgoing() async throws {
        let (center, service, engine, system) = makeCenter()
        var endedCalls = 0
        center.onCallEnded = { endedCalls += 1 }
        await center.startCall(to: peer, video: true)
        #expect(service.started.map(\.0) == ["20"])
        let control = try #require(engine.last)
        #expect(control.role == .caller)
        #expect(control.started == 1)
        #expect(control.camera == [true])
        let call = try #require(center.call)
        #expect(call.direction == .outgoing)
        #expect(call.conversationId == "out")
        #expect(system?.requests.first == .start(id: call.id, handle: "20", name: "Анна", video: true))

        control.move(to: .ringing)
        #expect(center.playsRingback)
        #expect(system?.connecting == [call.id])
        control.move(to: .active)
        #expect(!center.playsRingback)
        #expect(system?.connected == [call.id])

        await center.toggleMute()
        #expect(await eventually { control.muted == [true] })
        #expect(system?.requests.last == .mute(call.id, true))

        await center.hangUp()
        #expect(await eventually { control.hungUp == 1 })
        #expect(center.call?.state.phase == .ended(.hungUp))
        #expect(endedCalls == 1)
        // Сброс пришёл от системы: ей о конце не сообщают.
        #expect(system?.ended.isEmpty == true)
        #expect(await eventually { center.call == nil })
    }

    @Test("Сервер не дал позвонить: сообщение, экрана звонка нет, система узнаёт")
    func outgoingFails() async {
        let (center, service, engine, system) = makeCenter()
        service.startError = .networkUnavailable
        await center.startCall(to: peer, video: false)
        #expect(center.call == nil)
        #expect(center.errorMessage == MaxlyError.networkUnavailable.userMessage)
        #expect(engine.calls.isEmpty)
        #expect(system?.ended.count == 1)
        center.dismissError()
        #expect(center.errorMessage == nil)
    }

    @Test("Трубку положили, пока сервер отвечал: звонок у собеседника отменяется")
    func hangUpWhileStarting() async throws {
        let (center, service, engine, _) = makeCenter(system: nil)
        let gate = Gate()
        service.startGate = gate
        let starting = Task { await center.startCall(to: peer, video: false) }
        #expect(await eventually { await gate.arrivals == 1 })
        await center.hangUp()
        #expect(center.call?.state.isEnded == true)
        await gate.open()
        await starting.value
        let control = try #require(engine.last)
        #expect(control.started == 1)
        #expect(control.hungUp == 1)
    }

    @Test("Входящий: звонит системой, ответ через систему, собеседник положил трубку")
    func incomingAnswered() async throws {
        let (center, service, engine, system) = makeCenter()
        service.ring(incoming(video: true))
        #expect(await eventually { center.call != nil && engine.last?.started == 1 })
        let call = try #require(center.call)
        #expect(call.isRinging)
        #expect(call.peer.name == "Борис")
        #expect(engine.last?.role == .callee)
        #expect(system?.incoming.first?.2 == "Борис")
        #expect(CallStatusText.status(of: call, now: Date()) == "Входящий видеозвонок")

        await center.answer(video: true)
        let control = try #require(engine.last)
        #expect(await eventually { control.accepted == [true] })
        #expect(system?.requests == [.answer(call.id)])
        #expect(center.call?.isRinging == false)

        control.move(to: .active)
        control.move(to: .ended(.remoteHungUp))
        #expect(system?.ended.map(\.1) == [.remoteHungUp])
        let ended = try #require(center.call)
        #expect(CallStatusText.status(of: ended, now: Date()) == "Звонок завершён")
    }

    @Test("Входящий во время звонка и истёкший не показываются")
    func busyAndExpired() async throws {
        let (center, service, engine, _) = makeCenter()
        await center.startCall(to: peer, video: false)
        service.ring(incoming("second"))
        try await Task.sleep(for: .milliseconds(30))
        #expect(engine.calls.count == 1)
        #expect(center.call?.direction == .outgoing)

        let (idle, idleService, idleEngine, _) = makeCenter()
        idleService.ring(incoming("old", expiresAt: Date(timeIntervalSinceNow: -5)))
        try await Task.sleep(for: .milliseconds(30))
        #expect(idle.call == nil)
        #expect(idleEngine.calls.isEmpty)
    }

    @Test("Отклонить входящий; без системы ответ идёт прямо")
    func declineAndNoSystem() async throws {
        let (center, service, engine, system) = makeCenter()
        service.ring(incoming())
        #expect(await eventually { center.call != nil })
        await center.decline()
        #expect(await eventually { engine.last?.hungUp == 1 })
        #expect(center.call?.state.phase == .ended(.rejected))
        #expect(system?.ended.isEmpty == true)
        // Отклонение ушло и на основной сервер (167).
        #expect(await eventually { service.rejected == ["in-1"] })

        let (plain, plainService, plainEngine, _) = makeCenter(system: nil)
        plainService.ring(incoming())
        #expect(await eventually { plain.call != nil })
        await plain.answer()
        #expect(plainEngine.last?.accepted == [false])
    }

    @Test("Сервер не принял отклонение: звонок всё равно закрыт сокетом звонка")
    func declineRejectFails() async throws {
        let (center, service, engine, _) = makeCenter(system: nil)
        service.rejectError = .networkUnavailable
        service.ring(incoming())
        #expect(await eventually { center.call != nil })
        await center.decline()
        #expect(service.rejected == ["in-1"])
        #expect(engine.last?.hungUp == 1)
        #expect(center.call?.state.phase == .ended(.rejected))
    }

    @Test("Отбой после ответа и свой исходящий не уходят на сервер как отклонение")
    func hangUpIsNotReject() async throws {
        let (center, service, engine, _) = makeCenter(system: nil)
        service.ring(incoming())
        #expect(await eventually { center.call != nil })
        await center.answer()
        engine.last?.move(to: .active)
        await center.hangUp()
        #expect(engine.last?.hungUp == 1)
        #expect(service.rejected.isEmpty)
        #expect(await eventually { center.call == nil })

        await center.startCall(to: peer, video: false)
        await center.hangUp()
        #expect(service.rejected.isEmpty)
    }

    @Test("Пока звонок на экране, центр сообщает «занят»: приложение держит ядро активным")
    func busyHook() async throws {
        let (center, service, _, _) = makeCenter(system: nil)
        var busy: [Bool] = []
        center.onBusyChanged = { busy.append($0) }
        service.ring(incoming())
        #expect(await eventually { center.call != nil })
        #expect(busy == [true])
        await center.answer()
        #expect(busy == [true])
        await center.hangUp()
        #expect(await eventually { center.call == nil })
        #expect(busy == [true, false])
    }

    @Test("Система не приняла действие — центр делает его сам")
    func systemRefuses() async throws {
        let system = FakeCallSystem()
        system.refuseRequests = true
        let (center, service, engine, _) = makeCenter(system: system)
        service.ring(incoming())
        #expect(await eventually { center.call != nil })
        await center.answer()
        #expect(engine.last?.accepted == [false])
        await center.toggleMute()
        #expect(engine.last?.muted == [true])
        await center.hangUp()
        #expect(engine.last?.hungUp == 1)
        #expect(system.ended.count == 1)
    }

    @Test("Имя звонящего, которого нет в пуше, находится позже")
    func callerLookup() async throws {
        let (center, service, _, system) = makeCenter(lookup: { id in
            id == "30" ? CallCenter.Peer(id: "30", name: "Вера", avatarURL: URL(string: "https://a.test/v.jpg")) : nil
        })
        service.ring(incoming(name: ""))
        #expect(await eventually { center.call?.peer.name == "Вера" })
        #expect(center.call?.peer.avatarURL != nil)
        #expect(system?.incoming.first?.2 == "Звонок Max")
        #expect(system?.updates.first?.1 == "Вера")
    }

    @Test("Групповой по ссылке: название из ссылки, участники по именам")
    func joinByLink() async throws {
        let (center, service, engine, _) = makeCenter(lookup: { id in CallCenter.Peer(id: id, name: "Участник \(id)") })
        service.linkPreview = CallLinkPreview(url: URL(string: "https://max.ru/joincall/tok")!, name: "Планёрка", participants: 3)
        await center.join(link: " https://max.ru/joincall/tok ")
        #expect(service.joined == ["https://max.ru/joincall/tok"])
        let call = try #require(center.call)
        #expect(call.direction == .group)
        #expect(call.peer.name == "Планёрка")
        #expect(call.joinLink?.absoluteString == "https://max.ru/joincall/tok")
        let control = try #require(engine.last)
        #expect(control.role == .joiner)
        #expect(control.isGroup)
        var state = control.state
        state.participants = [CallParticipant(id: 1, isSelf: true), CallParticipant(id: 5, userId: "500")]
        control.state = state
        #expect(await eventually { center.name(ofUser: "500") == "Участник 500" })

        let link = await center.createLink()
        #expect(link?.name == "Созвон")
    }

    @Test("Кнопки звонка доходят до звонка; свернуть и развернуть")
    func controls() async throws {
        let (center, _, engine, _) = makeCenter(system: nil)
        await center.startCall(to: peer, video: false)
        let control = try #require(engine.last)
        await center.toggleCamera()
        await center.switchCamera()
        center.toggleSpeaker()
        await center.toggleScreenSharing()
        await center.toggleRecording()
        await center.invite(userIds: ["7"])
        #expect(control.camera == [true])
        #expect(control.cameraSwitches == 1)
        #expect(control.speaker == [true])
        #expect(control.screen == [true])
        #expect(control.recording == [true])
        #expect(control.invited == [["7"]])
        center.minimize()
        #expect(!center.isExpanded)
        center.expand()
        #expect(center.isExpanded)
        await center.startCall(to: peer, video: false)
        #expect(center.errorMessage == "Сначала закончите текущий звонок")
        await center.deactivate()
        #expect(control.hungUp == 1)
    }
}

@Suite("Подписи звонка")
@MainActor
struct CallStatusTextTests {
    private func call(_ phase: CallState.Phase, direction: CallCenter.Direction = .outgoing, answered: Bool = true,
                      since: Date? = nil, connected: Bool = true, participants: Int = 2) -> CallCenter.Call {
        var state = CallState()
        state.phase = phase
        state.activeSince = since
        state.mediaConnected = connected
        state.participants = (0..<participants).map { CallParticipant(id: Int64($0), isSelf: $0 == 0) }
        return CallCenter.Call(
            id: UUID(), conversationId: "c", direction: direction, peer: CallCenter.Peer(id: "1", name: "Анна"),
            isVideo: false, joinLink: nil, state: state, answered: answered
        )
    }

    @Test("Статус по фазе")
    func statuses() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(65)
        #expect(CallStatusText.status(of: call(.connecting), now: now) == "Соединение…")
        #expect(CallStatusText.status(of: call(.ringing), now: now) == "Вызов…")
        #expect(CallStatusText.status(of: call(.ringing, direction: .incoming, answered: false), now: now) == "Входящий звонок")
        #expect(CallStatusText.status(of: call(.active, since: start), now: now) == "1:05")
        #expect(CallStatusText.status(of: call(.active, since: start, connected: false), now: now) == "Соединение…")
        #expect(CallStatusText.status(of: call(.active, direction: .group, since: start, participants: 3), now: now) == "1:05 · 3 участника")
        #expect(CallStatusText.status(of: call(.reconnecting), now: now) == "Переподключение…")
        #expect(CallStatusText.status(of: call(.ended(.busy)), now: now) == "Абонент занят")
        #expect(CallStatusText.ended(.failed("")) == "Не удалось позвонить")
        #expect(CallStatusText.ended(.declined) == "Звонок отклонён")
        #expect(CallStatusText.ended(.noAnswer) == "Нет ответа")
    }

    @Test("Длительность и число участников")
    func formats() {
        #expect(CallStatusText.duration(42) == "0:42")
        #expect(CallStatusText.duration(725) == "12:05")
        #expect(CallStatusText.duration(3723) == "1:02:03")
        #expect(CallStatusText.duration(-3) == "0:00")
        #expect(CallStatusText.participants(1) == "1 участник")
        #expect(CallStatusText.participants(4) == "4 участника")
        #expect(CallStatusText.participants(11) == "11 участников")
        #expect(CallStatusText.participants(21) == "21 участник")
        #expect(CallStatusText.participants(25) == "25 участников")
    }
}
