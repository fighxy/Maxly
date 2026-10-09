import Foundation
import Observation
import OrbitleDomain

/// Действие пользователя, которое сначала идёт через системный экран звонка (CallKit), чтобы
/// система знала о нём: ответ с экрана приложения, сброс, микрофон.
public enum CallSystemAction: Hashable, Sendable {
    case start(id: UUID, handle: String, name: String, video: Bool)
    case answer(UUID)
    case end(UUID)
    case mute(UUID, Bool)
}

/// Системный экран звонка (CallKit). Приложение передаёт его центру звонков; без него
/// (тесты, превью) центр делает всё сам.
@MainActor
public protocol CallSystem: AnyObject {
    var delegate: (any CallSystemDelegate)? { get set }
    /// Входящий: система звонит своим экраном, в том числе на заблокированном телефоне.
    /// Ошибка — система не стала звонить (режим «Не беспокоить», блокировка).
    func reportIncoming(id: UUID, handle: String, name: String, video: Bool) async throws
    /// Попросить систему выполнить действие. Выполняет его делегат.
    func request(_ action: CallSystemAction) async throws
    /// Исходящий начал соединяться.
    func reportConnecting(id: UUID)
    /// Разговор начался.
    func reportConnected(id: UUID)
    /// Звонок закончился не по действию через систему: собеседник положил трубку, связь пропала.
    func reportEnded(id: UUID, reason: CallEndReason)
    /// Имя звонящего стало известно позже.
    func reportUpdate(id: UUID, name: String, video: Bool)
}

/// Действия, пришедшие с системного экрана звонка.
@MainActor
public protocol CallSystemDelegate: AnyObject {
    func systemAnswered(_ id: UUID)
    func systemEnded(_ id: UUID)
    func systemMuted(_ id: UUID, muted: Bool)
    /// Система сбросила все звонки (например, перезапуск её службы).
    func systemReset()
}

/// Центр звонков: один звонок на всё приложение — исходящий, входящий или групповой.
///
/// Входящие приходят пушем сервера: центр открывает сигнальный сокет (так видно, если
/// звонящий сбросил), сообщает системе и показывает экран звонка. Ответ, сброс и микрофон
/// идут через системный экран (CallKit), если он есть.
@MainActor
@Observable
public final class CallCenter: CallSystemDelegate {
    public enum Direction: Hashable, Sendable {
        case outgoing, incoming, group
    }

    /// С кем звонок: пользователь Max или групповой звонок.
    public struct Peer: Hashable, Sendable {
        public var id: String
        public var name: String
        public var avatarURL: URL?
        public var isGroup: Bool

        public init(id: String, name: String, avatarURL: URL? = nil, isGroup: Bool = false) {
            self.id = id
            self.name = name
            self.avatarURL = avatarURL
            self.isGroup = isGroup
        }
    }

    /// Звонок на экране.
    public struct Call: Identifiable, Hashable, Sendable {
        /// Id звонка для системы (CallKit).
        public let id: UUID
        public var conversationId: String
        public var direction: Direction
        public var peer: Peer
        public var isVideo: Bool
        public var joinLink: URL?
        public var state: CallState
        /// Входящий: на него уже ответили.
        public var answered: Bool

        /// Входящий, на который ещё не ответили: на экране кнопки «Ответить» и «Отклонить».
        public var isRinging: Bool {
            direction == .incoming && !answered && !state.isEnded
        }
    }

    public private(set) var call: Call? {
        didSet {
            let busy = call != nil
            if busy != (oldValue != nil) { onBusyChanged?(busy) }
        }
    }
    /// Экран звонка развёрнут; свёрнутый — плашка над приложением.
    public var isExpanded = true
    public private(set) var errorMessage: String?
    /// Имена участников групповых звонков по id пользователя Max.
    public private(set) var names: [String: Peer] = [:]
    /// Звонок закончился: приложение обновляет журнал звонков.
    @ObservationIgnored public var onCallEnded: (() -> Void)?
    /// Звонок появился (`true`) или ушёл с экрана (`false`). Пока он есть, приложение держит
    /// ядро «на экране» (`setAppActive(true)`), даже свёрнутое: так сервер не считает аккаунт ушедшим.
    @ObservationIgnored public var onBusyChanged: ((Bool) -> Void)?

    /// Исходящий звонит у собеседника: играют гудки.
    public var playsRingback: Bool {
        guard let call else { return false }
        return call.direction == .outgoing && call.state.phase == .ringing
    }

    @ObservationIgnored private let service: any CallService
    @ObservationIgnored private let engine: any CallEngine
    @ObservationIgnored private weak var system: (any CallSystem)?
    @ObservationIgnored private let lookup: @Sendable (String) async -> Peer?
    @ObservationIgnored private let endedDisplay: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var control: (any CallControl)?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private var answerWithVideo = false
    /// Звонок закончили через систему: ей не нужно сообщать о конце.
    @ObservationIgnored private var endedViaSystem: Set<UUID> = []
    @ObservationIgnored private var lookedUp: Set<String> = []

    public init(
        service: any CallService,
        engine: any CallEngine,
        system: (any CallSystem)? = nil,
        lookup: @escaping @Sendable (String) async -> Peer? = { _ in nil },
        endedDisplay: Duration = .milliseconds(1500),
        now: @escaping () -> Date = { Date() }
    ) {
        self.service = service
        self.engine = engine
        self.system = system
        self.lookup = lookup
        self.endedDisplay = endedDisplay
        self.now = now
    }

    /// Слушать входящие звонки.
    public func activate() {
        system?.delegate = self
        guard watch == nil else { return }
        let stream = service.incomingCalls()
        watch = Task { [weak self] in
            for await incoming in stream {
                guard let self else { return }
                await self.receive(incoming)
            }
        }
    }

    /// Выход из аккаунта: входящие больше не слушаются, идущий звонок кладётся.
    public func deactivate() async {
        watch?.cancel()
        watch = nil
        if call != nil { await hangUp() }
    }

    // MARK: Начать

    /// Позвонить пользователю Max.
    public func startCall(to peer: Peer, video: Bool) async {
        guard call == nil else {
            errorMessage = "Сначала закончите текущий звонок"
            return
        }
        let id = UUID()
        call = Call(id: id, conversationId: "", direction: .outgoing, peer: peer, isVideo: video, state: CallState(), answered: true)
        isExpanded = true
        errorMessage = nil
        do {
            let connection = try await service.startCall(peerId: peer.id, isVideo: video)
            let control = engine.makeCall(connection: connection, role: .caller, isGroup: false)
            guard call?.id == id, call?.state.isEnded == false else {
                // Трубку положили, пока сервер отвечал: звонок у собеседника надо отменить.
                await control.start()
                await control.hangUp()
                return
            }
            call?.conversationId = connection.conversationId
            attach(control, to: id)
            try? await system?.request(.start(id: id, handle: peer.id, name: peer.name, video: video))
            if video { await control.setCamera(true) }
            await control.start()
        } catch {
            fail(id, error)
        }
    }

    /// Войти в групповой звонок по ссылке.
    public func join(link: String, video: Bool = false) async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard call == nil else {
            errorMessage = "Сначала закончите текущий звонок"
            return
        }
        let id = UUID()
        let peer = Peer(id: "", name: "Групповой звонок", isGroup: true)
        call = Call(id: id, conversationId: "", direction: .group, peer: peer, isVideo: video, state: CallState(), answered: true)
        isExpanded = true
        errorMessage = nil
        do {
            let preview = try? await service.preview(link: trimmed)
            let connection = try await service.join(link: trimmed, isVideo: video)
            let control = engine.makeCall(connection: connection, role: .joiner, isGroup: true)
            guard call?.id == id, call?.state.isEnded == false else {
                await control.start()
                await control.hangUp()
                return
            }
            if let name = preview?.name { call?.peer.name = name }
            call?.conversationId = connection.conversationId
            call?.joinLink = connection.joinLink ?? preview?.url ?? URL(string: trimmed)
            attach(control, to: id)
            let title = call?.peer.name ?? peer.name
            try? await system?.request(.start(id: id, handle: connection.conversationId, name: title, video: video))
            if video { await control.setCamera(true) }
            await control.start()
        } catch {
            fail(id, error)
        }
    }

    /// Создать групповой звонок со ссылкой. Войти в него — `join(link:)`.
    public func createLink() async -> CallLink? {
        do {
            let link = try await service.createLink()
            errorMessage = nil
            return link
        } catch {
            errorMessage = error.userMessage
            return nil
        }
    }

    // MARK: Входящий

    func receive(_ incoming: IncomingCall) async {
        guard call == nil else {
            Log.info(.calls, "Входящий \(incoming.conversationId) во время звонка — не беру")
            return
        }
        if let expiresAt = incoming.expiresAt, expiresAt <= now() {
            Log.info(.calls, "Входящий \(incoming.conversationId) уже истёк")
            return
        }
        let id = UUID()
        let peer = Peer(id: incoming.callerId, name: incoming.callerName, avatarURL: incoming.callerAvatarURL)
        var state = CallState()
        state.phase = .ringing
        call = Call(
            id: id, conversationId: incoming.conversationId, direction: .incoming, peer: peer,
            isVideo: incoming.isVideo, state: state, answered: false
        )
        isExpanded = true
        let control = engine.makeCall(connection: incoming.connection, role: .callee, isGroup: false)
        attach(control, to: id)
        if let system {
            do {
                try await system.reportIncoming(id: id, handle: incoming.callerId, name: displayName(peer), video: incoming.isVideo)
            } catch {
                Log.info(.calls, "Система не показала входящий: \(error)")
            }
        }
        if incoming.callerName.isEmpty { resolveCaller(incoming.callerId, for: id) }
        await control.start()
    }

    /// Ответить на входящий.
    public func answer(video: Bool = false) async {
        guard let call, call.isRinging else { return }
        answerWithVideo = video
        if let system {
            do {
                try await system.request(.answer(call.id))
                return
            } catch {
                Log.info(.calls, "Ответ через систему не прошёл: \(error)")
            }
        }
        await performAnswer(call.id)
    }

    /// Отклонить входящий.
    public func decline() async {
        await hangUp()
    }

    /// Положить трубку.
    public func hangUp() async {
        guard let call else { return }
        if call.state.isEnded {
            dismiss(call.id)
            return
        }
        if let system {
            do {
                try await system.request(.end(call.id))
                return
            } catch {
                Log.info(.calls, "Сброс через систему не прошёл: \(error)")
            }
        }
        await performEnd(call.id)
    }

    // MARK: Во время звонка

    public func toggleMute() async {
        guard let call, !call.state.isEnded else { return }
        let muted = !call.state.muted
        if let system {
            do {
                try await system.request(.mute(call.id, muted))
                return
            } catch {
                Log.info(.calls, "Микрофон через систему не переключился: \(error)")
            }
        }
        await control?.setMuted(muted)
    }

    public func toggleCamera() async {
        guard let call, let control, !call.state.isEnded else { return }
        await control.setCamera(!call.state.cameraOn)
    }

    public func switchCamera() async {
        await control?.switchCamera()
    }

    public func toggleSpeaker() {
        guard let call, let control, !call.state.isEnded else { return }
        control.setSpeaker(!call.state.speakerOn)
    }

    public func toggleScreenSharing() async {
        guard let call, let control, !call.state.isEnded else { return }
        await control.setScreenSharing(!call.state.screenSharing)
    }

    public func toggleRecording() async {
        guard let call, let control, !call.state.isEnded else { return }
        await control.setRecording(!call.state.recording)
    }

    /// Позвать в идущий звонок пользователей Max.
    public func invite(userIds: [String]) async {
        guard let control else { return }
        do {
            try await control.invite(userIds: userIds)
        } catch {
            errorMessage = "Не удалось позвать в звонок"
        }
    }

    public func expand() { isExpanded = true }

    public func minimize() {
        guard call != nil else { return }
        isExpanded = false
    }

    public func dismissError() {
        errorMessage = nil
    }

    /// Показать сообщение о звонке (например, нет доступа к микрофону).
    public func showError(_ message: String) {
        errorMessage = message
    }

    /// Имя для экрана: участник группового звонка или собеседник.
    public func name(ofUser userId: String?) -> String? {
        guard let userId else { return nil }
        if call?.peer.id == userId, let name = call?.peer.name, !name.isEmpty { return name }
        return names[userId]?.name
    }

    // MARK: CallSystemDelegate

    public func systemAnswered(_ id: UUID) {
        Task { await self.performAnswer(id) }
    }

    public func systemEnded(_ id: UUID) {
        endedViaSystem.insert(id)
        Task { await self.performEnd(id) }
    }

    public func systemMuted(_ id: UUID, muted: Bool) {
        guard call?.id == id else { return }
        Task { await self.control?.setMuted(muted) }
    }

    public func systemReset() {
        guard let id = call?.id else { return }
        endedViaSystem.insert(id)
        Task { await self.performEnd(id) }
    }

    // MARK: Внутреннее

    private func performAnswer(_ id: UUID) async {
        guard let call, call.id == id, call.isRinging, let control else { return }
        self.call?.answered = true
        isExpanded = true
        await control.accept(video: answerWithVideo)
    }

    private func performEnd(_ id: UUID) async {
        guard let call, call.id == id else { return }
        // Отклонение входящего уходит и на основной сервер (167): у звонящего сразу «отклонён»,
        // даже если сокет звонка ещё не открылся. Сокет звонка тоже получает отбой.
        var rejection: Task<Void, Never>?
        if call.isRinging, !call.conversationId.isEmpty {
            let service = self.service
            let conversationId = call.conversationId
            rejection = Task {
                do {
                    try await service.reject(conversationId: conversationId, peerId: "")
                } catch {
                    Log.warning(.calls, "Сервер не принял отклонение \(conversationId): \(error)")
                }
            }
        }
        if let control {
            await control.hangUp()
        } else {
            // Сервер ещё не ответил на звонок: экран закрывается сразу.
            var state = call.state
            state.phase = .ended(.hungUp)
            update(id, state)
        }
        await rejection?.value
    }

    private func attach(_ control: any CallControl, to id: UUID) {
        self.control = control
        control.onChange = { [weak self] state in
            self?.update(id, state)
        }
        update(id, control.state)
    }

    private func update(_ id: UUID, _ state: CallState) {
        guard var call, call.id == id else { return }
        let previous = call.state
        if call.direction == .incoming, !call.answered, state.phase != .ringing, !state.isEnded {
            call.answered = true
        }
        call.state = state
        self.call = call
        if call.direction != .incoming {
            if previous.phase == .connecting, state.phase == .ringing { system?.reportConnecting(id: id) }
            if previous.activeSince == nil, state.activeSince != nil { system?.reportConnected(id: id) }
        }
        resolveParticipants(state.participants)
        if case .ended(let reason) = state.phase, !previous.isEnded {
            finished(id, reason)
        }
    }

    private func finished(_ id: UUID, _ reason: CallEndReason) {
        control = nil
        if endedViaSystem.remove(id) == nil {
            system?.reportEnded(id: id, reason: reason)
        }
        onCallEnded?()
        dismissal?.cancel()
        let delay = endedDisplay
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    private func dismiss(_ id: UUID) {
        guard call?.id == id else { return }
        call = nil
        isExpanded = true
        dismissal?.cancel()
        dismissal = nil
    }

    private func fail(_ id: UUID, _ error: OrbitleError) {
        Log.warning(.calls, "Звонок не начался: \(error)")
        errorMessage = error.userMessage ?? "Не удалось позвонить"
        if endedViaSystem.remove(id) == nil {
            system?.reportEnded(id: id, reason: .failed(errorMessage ?? ""))
        }
        if call?.id == id {
            call = nil
            isExpanded = true
        }
    }

    private func displayName(_ peer: Peer) -> String {
        peer.name.isEmpty ? "Звонок Max" : peer.name
    }

    private func resolveCaller(_ userId: String, for id: UUID) {
        let lookup = self.lookup
        Task { [weak self] in
            guard let found = await lookup(userId) else { return }
            guard let self, var call = self.call, call.id == id else { return }
            if call.peer.name.isEmpty { call.peer.name = found.name }
            if call.peer.avatarURL == nil { call.peer.avatarURL = found.avatarURL }
            self.call = call
            self.system?.reportUpdate(id: id, name: self.displayName(call.peer), video: call.isVideo)
        }
    }

    private func resolveParticipants(_ participants: [CallParticipant]) {
        let unknown = participants.compactMap(\.userId).filter { names[$0] == nil && !lookedUp.contains($0) && $0 != call?.peer.id }
        guard !unknown.isEmpty else { return }
        lookedUp.formUnion(unknown)
        let lookup = self.lookup
        for userId in unknown {
            Task { [weak self] in
                guard let found = await lookup(userId) else { return }
                self?.names[userId] = found
            }
        }
    }
}

/// Подписи экрана звонка.
public enum CallStatusText {
    /// Строка под именем: «Вызов…», «Входящий видеозвонок», «1:05», «Переподключение…».
    public static func status(of call: CallCenter.Call, now: Date) -> String {
        switch call.state.phase {
        case .connecting:
            if call.direction == .incoming, !call.answered { return incomingTitle(video: call.isVideo) }
            return "Соединение…"
        case .ringing:
            return call.direction == .incoming ? incomingTitle(video: call.isVideo) : "Вызов…"
        case .active:
            guard call.state.mediaConnected || call.state.topology == .server, let since = call.state.activeSince else {
                return "Соединение…"
            }
            let elapsed = duration(Int(now.timeIntervalSince(since)))
            if call.direction == .group || call.state.others.count > 1 {
                return "\(elapsed) · \(participants(call.state.participants.count))"
            }
            return elapsed
        case .reconnecting:
            return "Переподключение…"
        case .ended(let reason):
            return ended(reason)
        }
    }

    public static func incomingTitle(video: Bool) -> String {
        video ? "Входящий видеозвонок" : "Входящий звонок"
    }

    public static func ended(_ reason: CallEndReason) -> String {
        switch reason {
        case .hungUp, .remoteHungUp: "Звонок завершён"
        case .declined: "Звонок отклонён"
        case .busy: "Абонент занят"
        case .noAnswer: "Нет ответа"
        case .rejected: "Вы отклонили звонок"
        case .missed: "Пропущенный звонок"
        case .connectionLost: "Связь прервалась"
        case .failed(let message): message.isEmpty ? "Не удалось позвонить" : message
        }
    }

    /// `0:42`, `12:05`, `1:02:03`.
    public static func duration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// «3 участника», «5 участников».
    public static func participants(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        let word: String
        if (11...14).contains(mod100) {
            word = "участников"
        } else if mod10 == 1 {
            word = "участник"
        } else if (2...4).contains(mod10) {
            word = "участника"
        } else {
            word = "участников"
        }
        return "\(count) \(word)"
    }
}
