import Foundation
import MaxlyDomain

/// Один звонок: сигнальный сокет ws2 сервера звонков и WebRTC.
///
/// Протокол — схема Komet (`call_session.dart`, `ws2_signaling.dart`), код свой:
/// 1. Сокет ws2 открывается по адресу из ответа на звонок или из пуша входящего.
/// 2. Сервер присылает `connection`: участники, топология и серверы ICE.
/// 3. Напрямую (`DIRECT`): звонящий шлёт офер собеседнику через `transmit-data`, тот отвечает,
///    кандидаты ICE идут так же. Кандидаты до удалённого SDP придерживаются.
/// 4. Через сервер (`SERVER`, SFU): `allocate-consumer`, сервер шлёт офер в `producer-updated`,
///    ответ уходит в `accept-producer` вместе с номерами ssrc.
/// 5. `accept-call` — ответить; `hangup` — положить трубку с причиной.
///
/// Входящий до ответа уже держит сокет открытым: так видно, что звонящий сбросил. Офер,
/// пришедший до ответа, ждёт его.
@MainActor
public final class CallSession: CallControl {
    /// Задержки и пределы. Тесты ставят свои, чтобы не ждать.
    public struct Timing: Sendable {
        /// Сколько ждать `connection`, прежде чем толкнуть сервер командой.
        public var wake: Duration = .milliseconds(1200)
        /// Сколько ждать сбора кандидатов перед ответом SFU.
        public var gathering: Duration = .seconds(5)
        /// Сколько звонить собеседнику без ответа.
        public var outgoingRing: Duration = .seconds(90)
        /// Сколько звонит входящий, если сервер не сказал срок.
        public var incomingRing: Duration = .seconds(60)
        /// Паузы между попытками переподключения.
        public var reconnect: [Duration] = [1, 2, 4, 8, 16, 20, 20, 20, 20, 20, 20, 20].map { .seconds($0) }
        /// Как часто мерить уровень звука для подсветки говорящего.
        public var levels: Duration = .milliseconds(400)
        /// Сколько раз перезапускать ICE, пока не сдаться.
        public var iceRestarts = 6

        public init() {}
    }

    public private(set) var state = CallState() {
        didSet { if state != oldValue { onChange?(state) } }
    }

    public var onChange: ((CallState) -> Void)?

    private let connection: CallConnection
    private let role: CallRole
    private let isGroup: Bool
    private let media: any CallMedia
    private let connector: Ws2Connector
    private let timing: Timing
    private let now: () -> Date
    private let expiresAt: Date?

    private var signaling: Ws2Signaling?
    private var listener: Task<Void, Never>?
    private var peer: (any CallPeer)?
    private var target: CallPeerAddress?
    private var iceServers: [CallIceServer]
    private var topology: CallTopology = .direct
    private var gotConnection = false
    private var acceptSent = false
    /// Входящий: пользователь ответил.
    private var answered: Bool
    private var remoteSet = false
    private var pendingCandidates: [IceCandidate] = []
    /// Входящий до ответа: `transmitted-data`, которое ждёт ответа.
    private var held: [JSONValue] = []
    private var members: [Int64: CallParticipant] = [:]
    private var memberOrder: [Int64] = []
    private var cameraTracks: [Int64: String] = [:]
    private var screenTracks: [Int64: String] = [:]
    private var speaking: Set<Int64> = []
    private var speakHold: [Int64: Int] = [:]
    private var sfuSession: JSONValue?
    private var sfuChannels: [any CallDataChannel] = []
    private var sfuCommand: (any CallDataChannel)?
    private var sfuAliases: [Int: String] = [:]
    private var slotOwners: [Int: TrackOwner] = [:]
    /// SFU: `mid` слота своего видео из последнего офера сервера, если ответ отдал в него видео.
    /// Пусто — слот не согласован на отправку, видео попадёт в него со следующим офером.
    private var slotMids: Set<String> = []
    /// Что сейчас в слоте: экран, камера или ничего.
    private var slotVideo: LocalVideo?
    /// Под какой подписью сервер знает видео слота (последний `accept-producer`).
    private var slotLabel: LocalVideo?
    /// Номера ssrc из последнего офера сервера: они повторяются в каждом `accept-producer`.
    private var producerSsrcs: [String] = []
    private var layoutSequence = 1
    private var lastLayout: [String]?
    private var ended = false
    private var reconnecting = false
    private var iceRestarts = 0
    private var gatherWaiter: CheckedContinuation<Void, Never>?
    private var ringTimer: Task<Void, Never>?
    private var levelTimer: Task<Void, Never>?

    public init(
        connection: CallConnection,
        role: CallRole,
        isGroup: Bool = false,
        media: any CallMedia,
        connector: @escaping Ws2Connector,
        timing: Timing = Timing(),
        expiresAt: Date? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.connection = connection
        self.role = role
        self.isGroup = isGroup || role == .joiner
        self.media = media
        self.connector = connector
        self.timing = timing
        self.expiresAt = expiresAt
        self.now = now
        self.iceServers = connection.iceServers
        self.answered = role != .callee
        state.phase = role == .callee ? .ringing : .connecting
        let me = CallParticipant(id: connection.selfId, isSelf: true)
        members[me.id] = me
        memberOrder = [me.id]
        publish()
    }

    // MARK: CallControl

    public func start() async {
        guard signaling == nil, !ended else { return }
        do {
            try await openSignaling()
        } catch {
            Log.warning(.calls, "ws2 не открылся: \(error)")
            if role == .callee && !answered {
                end(.missed)
            } else {
                end(.failed("Сервер звонков недоступен"))
            }
            return
        }
        armRingTimer()
        startLevels()
    }

    public func accept(video: Bool) async {
        guard role == .callee, !answered, !ended else { return }
        answered = true
        ringTimer?.cancel()
        state.phase = .connecting
        if video { await turnCamera(on: true, announce: false) }
        if signaling == nil {
            await start()
            return
        }
        if gotConnection {
            await setUpMedia()
        } else if let signaling {
            scheduleWake(signaling)
        }
    }

    public func hangUp() async {
        guard !ended else { return }
        let reason = hangupReason()
        let local: CallEndReason = role == .callee && !answered ? .rejected : .hungUp
        let signaling = self.signaling
        end(local, closeSignaling: false)
        if let signaling {
            _ = try? await signaling.send("hangup", ["reason": .string(reason)])
            await signaling.close()
        } else if role == .callee {
            // Отклонить можно и до того, как сокет открылся: открыть, сказать и закрыть.
            if let socket = try? await Ws2Signaling.connect(url: connection.signalingURL, connector: connector) {
                _ = try? await socket.send("hangup", ["reason": .string(reason)])
                await socket.close()
            }
        }
    }

    public func setMuted(_ muted: Bool) async {
        guard !ended else { return }
        applyMuted(muted)
        await sendMediaSettings()
    }

    public func setCamera(_ on: Bool) async {
        guard !ended, on != state.cameraOn else { return }
        await turnCamera(on: on, announce: true)
    }

    public func switchCamera() async {
        guard !ended else { return }
        let next: CallCameraPosition = state.camera == .front ? .back : .front
        state.camera = next
        guard state.cameraOn else { return }
        do {
            try await media.startCamera(next)
        } catch {
            state.notice = "Не удалось переключить камеру"
        }
    }

    public func setScreenSharing(_ on: Bool) async {
        guard !ended, on != state.screenSharing else { return }
        if on {
            do {
                try await media.startScreen()
            } catch {
                state.notice = error == .denied ? "Запись экрана не разрешена" : "Не удалось показать экран"
                return
            }
            state.screenSharing = true
            if topology == .server {
                await refillSlot()
            } else if let peer {
                let added = peer.sendVideo(.screen)
                if added { await sendOffer() }
            }
        } else {
            if topology != .server || slotMids.isEmpty { peer?.stopVideo(.screen) }
            media.stopScreen()
            state.screenSharing = false
            // SFU: в освободившийся слот возвращается камера.
            if topology == .server { await refillSlot() }
        }
        updateLocalTrack()
        await sendMediaSettings()
        publishLayout()
    }

    public func setSpeaker(_ on: Bool) {
        guard !ended else { return }
        media.setSpeaker(on)
        state.speakerOn = on
    }

    public func setRecording(_ on: Bool) async {
        guard !ended, let signaling else { return }
        do {
            if on {
                try await signaling.send("record-start", Ws2Command.recordStart)
            } else {
                try await signaling.send("record-stop")
            }
            state.recording = on
        } catch {
            Log.warning(.calls, "Запись звонка: \(error)")
            state.notice = on ? "Запись недоступна" : "Не удалось остановить запись"
        }
    }

    public func invite(userIds: [String]) async throws(MaxlyError) {
        guard !userIds.isEmpty else { return }
        guard let signaling, !ended else { throw .invalidRequest }
        do {
            try await signaling.send("add-participant", ["externalIds": .array(userIds.map { .string($0) })])
        } catch {
            Log.warning(.calls, "Не позвали в звонок: \(error)")
            throw .invalidRequest
        }
    }

    /// Убрать показанное сообщение.
    public func dismissNotice() {
        state.notice = nil
    }

    // MARK: Сигнальный сокет

    private func openSignaling() async throws {
        let signaling = try await Ws2Signaling.connect(url: connection.signalingURL, connector: connector)
        guard !ended else {
            await signaling.close()
            return
        }
        self.signaling = signaling
        gotConnection = false
        listener = Task { [weak self] in
            for await message in signaling.notifications {
                guard let self else { return }
                await self.handle(message, from: signaling)
            }
            self?.signalingLost(signaling)
        }
        if answered { scheduleWake(signaling) }
    }

    /// Сервер иногда молчит после рукопожатия. Тогда его будит `change-media-settings`, а если и
    /// это не помогло — `accept-call` (так делает Komet).
    private func scheduleWake(_ signaling: Ws2Signaling) {
        let delay = timing.wake
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.isSilent(signaling) else { return }
            Log.info(.calls, "ws2 молчит — шлю change-media-settings")
            _ = try? await signaling.send("change-media-settings", ["mediaSettings": self.mediaSettings])
            try? await Task.sleep(for: delay)
            guard self.isSilent(signaling) else { return }
            Log.info(.calls, "ws2 всё ещё молчит — шлю accept-call")
            await self.sendAccept(activate: false)
        }
    }

    private func isSilent(_ signaling: Ws2Signaling) -> Bool {
        !ended && !gotConnection && self.signaling === signaling && answered
    }

    private func signalingLost(_ source: Ws2Signaling) {
        guard source === signaling, !ended, !reconnecting else { return }
        if role == .callee && !answered {
            end(.missed)
            return
        }
        Log.warning(.calls, "ws2 оборвался, переподключаюсь")
        Task { await self.reconnect() }
    }

    private func reconnect() async {
        reconnecting = true
        state.phase = .reconnecting
        for delay in timing.reconnect {
            try? await Task.sleep(for: delay)
            if ended { break }
            resetConnection()
            do {
                try await openSignaling()
                reconnecting = false
                return
            } catch {
                Log.warning(.calls, "Переподключение не удалось: \(error)")
            }
        }
        reconnecting = false
        if !ended { end(.connectionLost) }
    }

    /// Перед новой попыткой: старый сокет и соединение WebRTC закрываются, свои камера и
    /// микрофон остаются.
    private func resetConnection() {
        listener?.cancel()
        listener = nil
        if let old = signaling { Task { await old.close() } }
        signaling = nil
        closePeer()
        acceptSent = false
        sfuSession = nil
        gotConnection = false
    }

    // MARK: Уведомления

    private func handle(_ message: JSONValue, from source: Ws2Signaling) async {
        guard source === signaling, !ended else { return }
        if message["type"]?.string == "error" {
            Log.warning(.calls, "ws2 ошибка: \(message["error"]?.serialized() ?? "")")
            if message["error"]?.string == "conversation-ended" { end(closedReason()) }
            return
        }
        let name = message["notification"]?.string ?? ""
        if !answered && name == "transmitted-data" {
            held.append(message)
            return
        }
        if name != "connection" { applyMediaSettings(message) }
        switch name {
        case "connection": await onConnection(message)
        case "transmitted-data": await onTransmittedData(message)
        case "accepted-call": onAcceptedCall()
        case "participant-joined", "participant-added": onParticipantJoined(message)
        case "media-settings-changed": onParticipantMedia(message)
        case "participant-state-changed": onParticipantState(message)
        case "roles-changed": onRoles(message)
        case "participants-state-changed": onParticipantsState(message)
        case "participant-left", "participant-removed": onParticipantLeft(message)
        case "force-media-settings-change", "switch-micro": onForcedMedia(message)
        case "mute-participant": onMuteParticipant(message)
        case "hungup": onHungUp(message)
        case "topology-changed": await onTopologyChanged(message)
        case "producer-updated": await onProducerUpdated(message)
        case "closed-conversation": end(closedReason())
        default: break
        }
    }

    private func onConnection(_ message: JSONValue) async {
        gotConnection = true
        let conversation = message["conversation"]
        if let servers = Self.iceServers(from: message["conversationParams"]) { iceServers = servers }
        resolvePeer(conversation)
        resolveParticipants(conversation)
        if let features = conversation?["features"]?.array {
            state.recording = features.contains(.string("RECORD"))
        }
        if let raw = conversation?["topology"]?.string, let value = CallTopology(rawValue: raw) {
            topology = value
            state.topology = value
        }
        Log.info(.calls, "connection: роль \(role.rawValue), топология \(topology.rawValue), участников \(members.count)")
        guard answered else { return }
        await setUpMedia()
    }

    /// После `connection` (а у входящего — после ответа): соединение WebRTC и `accept-call`.
    private func setUpMedia() async {
        guard !ended, peer == nil else { return }
        if topology == .server {
            await sendAccept(activate: role != .caller)
            await setUpSfu()
            return
        }
        guard let peer = makePeer() else { return }
        peer.addMicrophone()
        if state.cameraOn { _ = peer.sendVideo(.camera) }
        if state.screenSharing { _ = peer.sendVideo(.screen) }
        peer.addVideoReceiver()
        if role == .caller {
            if state.activeSince == nil { state.phase = .ringing }
            await sendOffer()
        } else if role == .joiner {
            await sendOffer()
        }
        await sendAccept(activate: role != .caller)
        let waiting = held
        held = []
        for message in waiting {
            await onTransmittedData(message)
        }
    }

    private func onAcceptedCall() {
        guard role == .caller else { return }
        activate()
    }

    private func onTransmittedData(_ message: JSONValue) async {
        guard let peer else { return }
        // Собеседника не было в `connection`: отвечать тому, кто прислал.
        if target == nil, let from = CallSdp.participantId(message["participantId"]), from != connection.selfId {
            target = CallPeerAddress(
                id: from,
                type: message["participantType"]?.string ?? "USER",
                deviceIdx: message["deviceIdx"]?.int ?? 0
            )
        }
        let data = message["data"]
        if let sdp = data?["sdp"], let typeName = sdp["type"]?.string, let type = SdpType(rawValue: typeName),
           let text = sdp["sdp"]?.string {
            if type == .answer && peer.signalingState != .haveLocalOffer { return }
            if type == .offer && peer.signalingState == .haveLocalOffer {
                Log.info(.calls, "Встречный офер: откатываю свой")
                try? await peer.setLocal(SessionDescription(type: .rollback, sdp: ""))
            }
            do {
                try await peer.setRemote(SessionDescription(type: type, sdp: text))
            } catch {
                Log.warning(.calls, "Удалённый SDP не принят: \(error)")
                return
            }
            guard peer === self.peer else { return }
            remoteSet = true
            await flushCandidates()
            if type == .offer, let target {
                do {
                    let answer = try await peer.makeAnswer()
                    try await peer.setLocal(answer)
                    guard peer === self.peer else { return }
                    _ = try? await signaling?.send("transmit-data", Ws2Command.transmit(sdp: labeled(answer), to: target))
                } catch {
                    Log.warning(.calls, "Ответ на офер не собрался: \(error)")
                }
            }
            collectRemoteTracks()
            return
        }
        if let candidate = data?["candidate"], let line = candidate["candidate"]?.string {
            let ice = IceCandidate(
                sdp: line,
                sdpMid: candidate["sdpMid"]?.string,
                sdpMLineIndex: Int32(truncatingIfNeeded: candidate["sdpMLineIndex"]?.int ?? 0)
            )
            if remoteSet {
                await peer.add(ice)
            } else {
                pendingCandidates.append(ice)
            }
        }
    }

    private func onHungUp(_ message: JSONValue) {
        let raw = message["participantId"] ?? message["participant"]?["id"]
        guard let id = CallSdp.participantId(raw) else { return }
        if id == connection.selfId {
            end(.remoteHungUp)
            return
        }
        removeMember(id)
        guard !isGroup else { return }
        switch message["reason"]?.string?.uppercased() {
        case "REJECTED": end(role == .caller ? .declined : .remoteHungUp)
        case "BUSY": end(.busy)
        case "MISSED", "TIMEOUT": end(role == .caller ? .noAnswer : .missed)
        case "CANCELED": end(role == .callee && state.activeSince == nil ? .missed : .remoteHungUp)
        default: end(role == .callee && !answered ? .missed : .remoteHungUp)
        }
    }

    private func onTopologyChanged(_ message: JSONValue) async {
        guard let raw = message["topology"]?.string, let value = CallTopology(rawValue: raw) else { return }
        let toServer = value == .server && topology != .server
        topology = value
        state.topology = value
        if toServer, answered, peer != nil || gotConnection {
            await setUpSfu()
        }
    }

    // MARK: SFU

    private func setUpSfu() async {
        // Разговор шёл напрямую и переезжает на сервер — «переподключение»; иначе «соединение».
        let wasConnected = state.mediaConnected
        closePeer()
        state.phase = wasConnected ? .reconnecting : .connecting
        guard let peer = makePeer() else { return }
        peer.addMicrophone()
        // Слот своего видео у сервера один: в него идёт экран, иначе камера.
        if let outgoing = outgoingVideo { _ = peer.sendVideo(outgoing) }
        openSfuChannels(peer)
        do {
            try await signaling?.send("allocate-consumer", Ws2Command.allocateConsumer)
        } catch {
            Log.warning(.calls, "allocate-consumer: \(error)")
        }
    }

    private func onProducerUpdated(_ message: JSONValue) async {
        guard peer != nil else { return }
        let session = message["sessionId"].flatMap { $0.isNull ? nil : $0 }
        if let session, let previous = sfuSession, session != previous {
            Log.info(.calls, "SFU сменил сессию — пересобираю соединение")
            closePeer()
            guard let fresh = makePeer() else { return }
            fresh.addMicrophone()
            if let outgoing = outgoingVideo { _ = fresh.sendVideo(outgoing) }
            openSfuChannels(fresh)
        }
        if let session { sfuSession = session }
        guard let peer else { return }

        var sdp: String?
        var type = SdpType.offer
        switch message["description"] {
        case .string(let text)?:
            sdp = text
        case let description? where description.object != nil:
            sdp = description["sdp"]?.string ?? description["description"]?.string
            type = description["type"]?.string.flatMap(SdpType.init(rawValue:)) ?? .offer
        default:
            break
        }
        guard let sdp else {
            Log.warning(.calls, "producer-updated без SDP")
            return
        }
        let ssrcs = CallSdp.ssrcs(in: sdp)
        do {
            try await peer.setRemote(SessionDescription(type: type, sdp: sdp))
            guard peer === self.peer else { return }
            remoteSet = true
            await flushCandidates()
            for candidate in CallSdp.candidates(in: sdp) {
                await peer.add(candidate)
            }
            let mids = CallSdp.receiveOnlyVideoMids(in: sdp)
            slotMids = []
            slotVideo = nil
            if let outgoing = outgoingVideo, peer.fillVideoSlot(mids: mids, with: outgoing) {
                slotMids = mids
                slotVideo = outgoing
            }
            producerSsrcs = ssrcs
            let answer = try await peer.makeAnswer()
            guard peer === self.peer else { return }
            try await peer.setLocal(answer)
            guard peer === self.peer else { return }
            await waitForGathering(peer)
            guard peer === self.peer else { return }
            let local = peer.localDescription?.sdp ?? answer.sdp
            slotLabel = slotVideo
            try await signaling?.send("accept-producer", producerAnswer(local))
        } catch {
            Log.warning(.calls, "SFU: офер сервера не принят: \(error)")
            return
        }
        if acceptSent { await sendMediaSettings() }
        collectRemoteTracks()
        publishLayout(force: true)
    }

    private var outgoingVideo: LocalVideo? {
        if state.screenSharing { return .screen }
        if state.cameraOn { return .camera }
        return nil
    }

    /// Тело `accept-producer`: свой ответ с подписями, ssrc и сессия из офера сервера.
    private func producerAnswer(_ sdp: String) -> [String: JSONValue] {
        let description = labeled(SessionDescription(type: .answer, sdp: sdp))
        var body: [String: JSONValue] = ["description": .string(description.sdp)]
        if !producerSsrcs.isEmpty { body["ssrcs"] = .array(producerSsrcs.map { .string($0) }) }
        if let session = sfuSession { body["sessionId"] = session }
        return body
    }

    /// SFU: в единственный слот своего видео кладётся то, что сейчас главное (экран, иначе
    /// камера). Новый отправитель не добавляется: дорожка меняется в отправителе слота, а
    /// согласование не нужно. Но сервер узнаёт видео по подписи в SDP (`u<id>:sCAMERA` /
    /// `u<id>:sSCREEN`), а она осталась от прежней дорожки, поэтому тот же ответ уходит ещё раз
    /// `accept-producer` с новой подписью. Слот не согласован на отправку — видео ляжет в него
    /// со следующим офером сервера.
    private func refillSlot() async {
        guard topology == .server, let peer, !slotMids.isEmpty else { return }
        let wanted = outgoingVideo
        if wanted != slotVideo {
            if let wanted {
                peer.fillVideoSlot(mids: slotMids, with: wanted)
            } else if let current = slotVideo {
                peer.stopVideo(current)
            }
            slotVideo = wanted
        }
        guard let video = wanted, video != slotLabel, let local = peer.localDescription, local.type == .answer else { return }
        slotLabel = video
        Log.info(.calls, "SFU: в слоте своего видео теперь \(video.rawValue), шлю новую подпись")
        do {
            try await signaling?.send("accept-producer", producerAnswer(local.sdp))
        } catch {
            Log.warning(.calls, "accept-producer с новой подписью: \(error)")
        }
    }

    private func openSfuChannels(_ peer: any CallPeer) {
        closeSfuChannels()
        for label in [SfuChannel.commandLabel, SfuChannel.notificationLabel] {
            guard let channel = peer.openChannel(label: label) else { continue }
            if label == SfuChannel.commandLabel {
                sfuCommand = channel
                channel.onOpen = { [weak self] in self?.publishLayout(force: true) }
            } else {
                channel.onMessage = { [weak self] data in self?.onSfuNotification(data) }
            }
            sfuChannels.append(channel)
        }
    }

    private func closeSfuChannels() {
        sfuChannels.forEach { $0.close() }
        sfuChannels = []
        sfuCommand = nil
        sfuAliases = [:]
        slotOwners = [:]
        lastLayout = nil
    }

    private func onSfuNotification(_ data: Data) {
        guard !ended, let notification = SfuChannel.parse(data, aliases: sfuAliases) else { return }
        switch notification {
        case .aliases(let aliases):
            sfuAliases.merge(aliases) { _, new in new }
        case .slots(let slots):
            guard !slots.isEmpty else { return }
            slotOwners = [:]
            for (key, slot) in slots where slot >= 0 {
                var owner = CallSdp.owner(ofTrack: key)
                owner.slot = slot
                if owner.participant != nil { slotOwners[slot] = owner }
            }
            cameraTracks = [:]
            screenTracks = [:]
            collectRemoteTracks()
        case .levels(let levels):
            var loud = Set<Int64>()
            for (key, level) in levels where level >= 50 {
                if let id = CallSdp.owner(ofTrack: key).participant { loud.insert(id) }
            }
            if loud != speaking {
                speaking = loud
                publish()
            }
        }
    }

    /// Какие видео присылать: камера или экран каждого, у кого они включены, до 10 окон.
    private func publishLayout(force: Bool = false) {
        guard topology == .server, !ended, let channel = sfuCommand, channel.isOpen else { return }
        let items = others
            .filter { $0.videoOn || $0.screenOn }
            .prefix(10)
            .map { SfuChannel.LayoutItem(trackKey: CallSdp.layoutKey(participant: $0.id, screen: $0.screenOn)) }
        let keys = items.map(\.trackKey)
        if !force, let lastLayout, Set(lastLayout) == Set(keys) { return }
        if channel.send(SfuChannel.displayLayout(Array(items), sequence: layoutSequence)) {
            layoutSequence += 1
            lastLayout = keys
        }
    }

    // MARK: WebRTC

    private func makePeer() -> (any CallPeer)? {
        guard let peer = media.makePeer(iceServers: iceServers) else {
            end(.failed("Не удалось начать звонок"))
            return nil
        }
        peer.onEvent = { [weak self, weak peer] event in
            guard let self, let peer else { return }
            self.handlePeer(event, from: peer)
        }
        self.peer = peer
        remoteSet = false
        pendingCandidates = []
        return peer
    }

    private func closePeer() {
        closeSfuChannels()
        slotMids = []
        slotVideo = nil
        slotLabel = nil
        producerSsrcs = []
        resumeGathering()
        peer?.onEvent = nil
        peer?.close()
        peer = nil
        remoteSet = false
        pendingCandidates = []
        cameraTracks = [:]
        screenTracks = [:]
        state.mediaConnected = false
    }

    private func handlePeer(_ event: PeerEvent, from source: any CallPeer) {
        guard source === peer, !ended else { return }
        switch event {
        case .candidate(let candidate):
            if candidate.sdp.contains(" typ relay") { resumeGathering() }
            guard topology == .direct, let target, let signaling else { return }
            Task { _ = try? await signaling.send("transmit-data", Ws2Command.transmit(candidate: candidate, to: target)) }
        case .gatheringComplete:
            resumeGathering()
        case .state(let peerState):
            onPeerState(peerState)
        case .iceFailed:
            guard topology == .server, let signaling else { return }
            Log.warning(.calls, "SFU: ICE не прошёл — request-realloc")
            Task { _ = try? await signaling.send("request-realloc") }
        case .remoteTrack(let track):
            bind(track)
        }
    }

    private func onPeerState(_ peerState: PeerState) {
        let connected = peerState == .connected
        if connected != state.mediaConnected {
            state.mediaConnected = connected
            if connected {
                iceRestarts = 0
                if role != .caller || topology == .server || state.activeSince != nil {
                    activate()
                }
                collectRemoteTracks()
            }
        }
        guard topology == .direct else { return }
        switch peerState {
        case .failed:
            Task { await self.restartIce() }
        case .closed:
            end(.connectionLost)
        default:
            break
        }
    }

    private func restartIce() async {
        guard !ended, topology == .direct else { return }
        guard iceRestarts < timing.iceRestarts else {
            Log.warning(.calls, "ICE не восстановился")
            end(.connectionLost)
            return
        }
        iceRestarts += 1
        if state.activeSince != nil { state.phase = .reconnecting }
        pendingCandidates = []
        await sendOffer(iceRestart: true)
    }

    private func sendOffer(iceRestart: Bool = false) async {
        guard let peer, let target else { return }
        do {
            let offer = try await peer.makeOffer(iceRestart: iceRestart)
            guard peer === self.peer else { return }
            try await peer.setLocal(offer)
            guard peer === self.peer else { return }
            try await signaling?.send("transmit-data", Ws2Command.transmit(sdp: labeled(offer), to: target))
        } catch {
            Log.warning(.calls, "Офер не ушёл: \(error)")
        }
    }

    private func flushCandidates() async {
        guard let peer, !pendingCandidates.isEmpty else { return }
        let waiting = pendingCandidates
        pendingCandidates = []
        for candidate in waiting {
            await peer.add(candidate)
        }
    }

    /// SFU ждёт ответ со всеми кандидатами: ждём конца сбора или кандидата TURN, но не дольше
    /// `timing.gathering`.
    private func waitForGathering(_ peer: any CallPeer) async {
        guard !peer.isGatheringComplete else { return }
        resumeGathering()
        let limit = timing.gathering
        let timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            self?.resumeGathering()
        }
        await withCheckedContinuation { continuation in
            gatherWaiter = continuation
        }
        timer.cancel()
    }

    private func resumeGathering() {
        let waiter = gatherWaiter
        gatherWaiter = nil
        waiter?.resume()
    }

    /// Свои видеодорожки в SDP подписываются так, как их ищет сервер. В SFU слот своего видео
    /// подписывается по `mid` тем, что в нём сейчас: id дорожки в SDP мог остаться от прежней.
    private func labeled(_ description: SessionDescription) -> SessionDescription {
        var names: [String: String] = [:]
        if let camera = media.trackId(of: .camera) {
            names[camera] = CallSdp.layoutKey(participant: connection.selfId, screen: false)
        }
        if let screen = media.trackId(of: .screen) {
            names[screen] = CallSdp.layoutKey(participant: connection.selfId, screen: true)
        }
        var sdp = CallSdp.label(description.sdp, names: names)
        if topology == .server, let video = slotVideo {
            let key = CallSdp.layoutKey(participant: connection.selfId, screen: video == .screen)
            sdp = CallSdp.label(sdp, mids: slotMids, as: key)
        }
        return SessionDescription(type: description.type, sdp: sdp)
    }

    private func collectRemoteTracks() {
        guard let peer else { return }
        for track in peer.remoteTracks() {
            bind(track)
        }
    }

    /// Видео собеседника — к участнику: по id дорожки, по слоту SFU или, напрямую, к собеседнику.
    private func bind(_ track: RemoteTrack) {
        guard track.kind == .video else { return }
        var owner = CallSdp.owner(ofTrack: track.id)
        if let slot = owner.slot {
            guard let known = slotOwners[slot] else { return }
            owner = known
        }
        if owner.participant == nil, topology == .direct, let peerId = target?.id {
            owner.participant = peerId
            if let camera = cameraTracks[peerId], camera != track.id { owner.screen = true }
        }
        guard let id = owner.participant, id != connection.selfId else { return }
        if owner.screen {
            guard screenTracks[id] != track.id else { return }
            screenTracks[id] = track.id
        } else {
            guard cameraTracks[id] != track.id else { return }
            cameraTracks[id] = track.id
        }
        publish()
    }

    // MARK: Участники

    private func resolvePeer(_ conversation: JSONValue?) {
        guard !isGroup || target == nil else { return }
        for participant in conversation?["participants"]?.array ?? [] {
            guard let id = CallSdp.participantId(participant["id"]), id != connection.selfId else { continue }
            target = CallPeerAddress(
                id: id,
                type: participant["responderTypes"]?.array?.first?.string ?? target?.type ?? "USER",
                deviceIdx: participant["responderDeviceIdxs"]?.array?.first?.int ?? target?.deviceIdx ?? 0
            )
            return
        }
    }

    private func resolveParticipants(_ conversation: JSONValue?) {
        guard let list = conversation?["participants"]?.array else { return }
        var seen: Set<Int64> = [connection.selfId]
        for participant in list {
            guard let id = CallSdp.participantId(participant["id"]) else { continue }
            seen.insert(id)
            upsert(id, from: participant)
        }
        for id in memberOrder where !seen.contains(id) {
            members[id] = nil
        }
        memberOrder.removeAll { !seen.contains($0) }
        publish()
    }

    private func upsert(_ id: Int64, from source: JSONValue?, roles: JSONValue? = nil, hand: Bool? = nil) {
        var member = members[id] ?? CallParticipant(id: id, isSelf: id == connection.selfId)
        if members[id] == nil { memberOrder.append(id) }
        if let source {
            if let external = source["externalId"] {
                let value: JSONValue? = external.object != nil ? external["id"] : external
                if let userId = value?.int { member.userId = String(userId) } else if let text = value?.string, !text.isEmpty {
                    member.userId = text
                }
            }
            if let value = source["state"]?.string { member.state = value }
            if let settings = source["mediaSettings"], settings.object != nil {
                member.audioOn = settings["isAudioEnabled"]?.bool == true
                member.videoOn = settings["isVideoEnabled"]?.bool == true
                member.screenOn = settings["isScreenSharingEnabled"]?.bool == true
            }
            if let mutes = source["muteStates"], mutes.object != nil {
                if let audio = mutes["AUDIO"]?.string, audio != "UNMUTE" { member.audioOn = false }
                if let video = mutes["VIDEO"]?.string, video != "UNMUTE" { member.videoOn = false }
                if let screen = mutes["SCREEN_SHARING"]?.string, screen != "UNMUTE" { member.screenOn = false }
            }
            if let list = source["roles"]?.array { member.roles = list.compactMap(\.string) }
            if let value = Self.hand(source["participantState"]) { member.handRaised = value }
        }
        if let list = roles?.array { member.roles = list.compactMap(\.string) }
        if let hand { member.handRaised = hand }
        members[id] = member
    }

    private func removeMember(_ id: Int64) {
        guard id != connection.selfId, members[id] != nil else { return }
        members[id] = nil
        memberOrder.removeAll { $0 == id }
        cameraTracks[id] = nil
        screenTracks[id] = nil
        publish()
        publishLayout()
    }

    private func onParticipantJoined(_ message: JSONValue) {
        let source = message["participant"].flatMap { $0.object != nil ? $0 : nil } ?? message
        guard let id = CallSdp.participantId(source["id"] ?? source["participantId"] ?? message["participantId"]) else { return }
        upsert(id, from: source)
        adoptPeer(id, source)
        publish()
        publishLayout()
    }

    /// Вошедший по ссылке в звонок на двоих находит собеседника и шлёт ему офер.
    private func adoptPeer(_ id: Int64, _ source: JSONValue) {
        guard role == .joiner, target == nil, peer != nil, topology == .direct, id != connection.selfId else { return }
        target = CallPeerAddress(
            id: id,
            type: (source["participantType"] ?? source["idType"])?.string ?? "USER",
            deviceIdx: source["deviceIdx"]?.int ?? 0
        )
        Task { await self.sendOffer() }
    }

    private func onParticipantMedia(_ message: JSONValue) {
        guard let id = CallSdp.participantId(message["participantId"]) else { return }
        upsert(id, from: message)
        adoptPeer(id, message)
        publish()
        publishLayout()
    }

    private func onParticipantState(_ message: JSONValue) {
        guard let id = CallSdp.participantId(message["participantId"]) else { return }
        upsert(id, from: nil, hand: Self.hand(message["participantState"]))
        publish()
    }

    private func onRoles(_ message: JSONValue) {
        guard let id = CallSdp.participantId(message["participantId"]) else { return }
        upsert(id, from: nil, roles: message["roles"])
        publish()
    }

    private func onParticipantsState(_ message: JSONValue) {
        for participant in message["participants"]?.array ?? [] {
            guard let id = CallSdp.participantId(participant["participantId"] ?? participant["id"]) else { continue }
            upsert(id, from: participant)
        }
        publish()
        publishLayout()
    }

    private func onParticipantLeft(_ message: JSONValue) {
        guard let id = CallSdp.participantId(message["participantId"]) else { return }
        removeMember(id)
        if !isGroup, id == target?.id {
            end(.remoteHungUp)
        }
    }

    /// `mediaSettings` в любом уведомлении — о собеседнике (или об участнике из `participantId`).
    private func applyMediaSettings(_ message: JSONValue) {
        guard let settings = message["mediaSettings"], settings.object != nil else { return }
        let id = CallSdp.participantId(message["participantId"]) ?? target?.id
        guard let id, id != connection.selfId else { return }
        let before = members[id]
        upsert(id, from: ["mediaSettings": settings])
        if members[id] != before {
            publish()
            if members[id]?.videoOn == true || members[id]?.screenOn == true { collectRemoteTracks() }
        }
    }

    /// Админ включил или выключил наш микрофон.
    private func onForcedMedia(_ message: JSONValue) {
        var audioOn: Bool?
        if let value = message["mediaSettings"]?["isAudioEnabled"]?.bool { audioOn = value }
        if let value = message["muteStates"]?["AUDIO"]?.string { audioOn = value == "UNMUTE" }
        if let mute = message["mute"]?.bool { audioOn = !mute }
        guard let audioOn else { return }
        applyMuted(!audioOn)
    }

    private func onMuteParticipant(_ message: JSONValue) {
        guard let audio = message["muteStates"]?["AUDIO"]?.string else { return }
        let audioOn = audio == "UNMUTE"
        let subject = CallSdp.participantId(message["participantId"])
        if let subject, var member = members[subject], !member.isSelf {
            member.audioOn = audioOn
            members[subject] = member
            publish()
        }
        if message["muteAll"]?.bool == true || subject == nil || subject == connection.selfId {
            applyMuted(!audioOn)
        }
    }

    private static func hand(_ participantState: JSONValue?) -> Bool? {
        guard let state = participantState?["state"], let hand = state["hand"] else { return nil }
        return hand.string == "1" || hand.bool == true
    }

    private var others: [CallParticipant] {
        state.participants.filter { !$0.isSelf }
    }

    /// Собирает участников для экрана: свой — по своему состоянию, видео и «говорит» — сверху.
    private func publish() {
        state.participants = memberOrder.compactMap { id in
            guard var member = members[id] else { return nil }
            if member.isSelf {
                member.audioOn = !state.muted
                member.videoOn = state.cameraOn
                member.screenOn = state.screenSharing
                member.cameraTrack = media.trackId(of: .camera)
                member.screenTrack = media.trackId(of: .screen)
            } else {
                member.cameraTrack = cameraTracks[id]
                member.screenTrack = screenTracks[id]
            }
            member.speaking = speaking.contains(id)
            return member
        }
    }

    // MARK: Своё медиа

    private func turnCamera(on: Bool, announce: Bool) async {
        if on {
            do {
                try await media.startCamera(state.camera)
            } catch {
                state.notice = error == .denied ? "Нет доступа к камере" : "Камера недоступна"
                return
            }
            state.cameraOn = true
            if topology == .server {
                await refillSlot()
            } else if let peer {
                let added = peer.sendVideo(.camera)
                if added { await sendOffer() }
            }
        } else {
            if topology != .server || slotMids.isEmpty { peer?.stopVideo(.camera) }
            media.stopCamera()
            state.cameraOn = false
            if topology == .server { await refillSlot() }
        }
        updateLocalTrack()
        publish()
        if announce { await sendMediaSettings() }
    }

    private func updateLocalTrack() {
        state.localTrack = state.screenSharing ? media.trackId(of: .screen) : (state.cameraOn ? media.trackId(of: .camera) : nil)
    }

    private func applyMuted(_ muted: Bool) {
        state.muted = muted
        media.setMicrophone(enabled: !muted)
        publish()
    }

    /// В SFU слот своего видео один, и при показе экрана в нём экран: камера тогда только
    /// своё превью, и серверу говорится `video: false`, иначе другие ждут камеру, которой нет.
    private var mediaSettings: JSONValue {
        let screen = state.screenSharing
        let video = state.cameraOn && !(topology == .server && screen)
        return Ws2Command.mediaSettings(audio: !state.muted, video: video, screen: screen)
    }

    private func sendMediaSettings() async {
        guard let signaling else { return }
        _ = try? await signaling.send("change-media-settings", ["mediaSettings": mediaSettings])
    }

    private func sendAccept(activate: Bool) async {
        if !acceptSent, let signaling {
            acceptSent = true
            do {
                try await signaling.send("accept-call", ["mediaSettings": mediaSettings])
            } catch {
                Log.warning(.calls, "accept-call: \(error)")
            }
        }
        if activate { self.activate() }
    }

    private func activate() {
        guard !ended else { return }
        ringTimer?.cancel()
        if state.activeSince == nil { state.activeSince = now() }
        state.phase = .active
    }

    // MARK: Таймеры

    private func armRingTimer() {
        ringTimer?.cancel()
        let limit: Duration
        switch role {
        case .caller:
            limit = timing.outgoingRing
        case .callee where !answered:
            if let expiresAt {
                limit = .seconds(max(1, expiresAt.timeIntervalSince(now())))
            } else {
                limit = timing.incomingRing
            }
        default:
            return
        }
        ringTimer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled, let self, !self.ended, self.state.activeSince == nil else { return }
            if self.role == .caller {
                Log.info(.calls, "Собеседник не ответил")
                let signaling = self.signaling
                self.end(.noAnswer, closeSignaling: false)
                _ = try? await signaling?.send("hangup", ["reason": "CANCELED"])
                await signaling?.close()
            } else if !self.answered {
                self.end(.missed)
            }
        }
    }

    /// Подсветка говорящего напрямую — по уровням звука WebRTC. В SFU уровни шлёт сервер.
    private func startLevels() {
        levelTimer?.cancel()
        let interval = timing.levels
        levelTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !self.ended else { return }
                await self.sampleLevels()
            }
        }
    }

    private func sampleLevels() async {
        guard topology == .direct, state.mediaConnected, let peer, let levels = await peer.audioLevels() else { return }
        var loud = Set<Int64>()
        if !state.muted, levels.local > 0.05 { loud.insert(connection.selfId) }
        if levels.remote > 0.05, let id = target?.id { loud.insert(id) }
        for id in loud { speakHold[id] = 3 }
        for (id, ticks) in speakHold where !loud.contains(id) {
            speakHold[id] = ticks > 1 ? ticks - 1 : nil
        }
        let next = Set(speakHold.keys)
        if next != speaking {
            speaking = next
            publish()
        }
    }

    // MARK: Конец

    private func hangupReason() -> String {
        if state.activeSince == nil {
            if role == .caller { return "CANCELED" }
            if role == .callee && !answered { return "REJECTED" }
        }
        return "HUNGUP"
    }

    private func closedReason() -> CallEndReason {
        guard state.activeSince == nil else { return .remoteHungUp }
        switch role {
        case .caller: return .noAnswer
        case .callee: return answered ? .remoteHungUp : .missed
        case .joiner: return .remoteHungUp
        }
    }

    private func end(_ reason: CallEndReason, closeSignaling: Bool = true) {
        guard !ended else { return }
        ended = true
        Log.info(.calls, "Звонок закончен: \(reason)")
        ringTimer?.cancel()
        levelTimer?.cancel()
        listener?.cancel()
        closePeer()
        media.shutdown()
        if closeSignaling, let signaling { Task { await signaling.close() } }
        state.phase = .ended(reason)
    }

    // MARK: Разбор

    /// Серверы ICE из `conversationParams` уведомления `connection`: они главнее тех, что в пуше.
    static func iceServers(from params: JSONValue?) -> [CallIceServer]? {
        guard let params, params.object != nil else { return nil }
        var servers: [CallIceServer] = []
        if let stun = params["stun"], let urls = urls(stun["urls"]), !urls.isEmpty {
            servers.append(CallIceServer(urls: urls))
        }
        if let turn = params["turn"], let urls = urls(turn["urls"]), !urls.isEmpty {
            servers.append(CallIceServer(urls: urls, username: turn["username"]?.string, credential: turn["credential"]?.string))
        }
        return servers.isEmpty ? nil : servers
    }

    private static func urls(_ value: JSONValue?) -> [String]? {
        switch value {
        case .string(let text)?: return [text]
        case .array(let list)?: return list.compactMap(\.string)
        default: return nil
        }
    }
}

/// Звонки на `CallSession`: сокет `URLSessionWs2Socket` и медиа, которое даёт приложение.
@MainActor
public final class SessionCallEngine: CallEngine {
    private let makeMedia: @MainActor () -> any CallMedia
    private let connector: Ws2Connector

    public init(
        connector: @escaping Ws2Connector = { try await URLSessionWs2Socket.connect(url: $0) },
        makeMedia: @escaping @MainActor () -> any CallMedia
    ) {
        self.connector = connector
        self.makeMedia = makeMedia
    }

    public func makeCall(connection: CallConnection, role: CallRole, isGroup: Bool) -> any CallControl {
        CallSession(connection: connection, role: role, isGroup: isGroup, media: makeMedia(), connector: connector)
    }
}
