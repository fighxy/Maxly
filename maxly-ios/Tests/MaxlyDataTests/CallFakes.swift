import Foundation
import MaxlyDomain
@testable import MaxlyData

/// Сервер ws2 в памяти: отвечает на каждую команду по её номеру и шлёт уведомления по команде теста.
final class FakeWs2Server: Ws2Socket, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String] = []
    private var waiter: CheckedContinuation<String?, Never>?
    private var closed = false
    private var sentFrames: [JSONValue] = []
    private var sentTexts: [String] = []
    private var errors: [String: String] = [:]
    private var silent: Set<String> = []

    /// Команды, на которые сервер отвечает ошибкой.
    func fail(_ command: String, with error: String) {
        lock.withLock { errors[command] = error }
    }

    /// Команды, на которые сервер не отвечает вовсе.
    func ignore(_ command: String) {
        lock.withLock { _ = silent.insert(command) }
    }

    var frames: [JSONValue] { lock.withLock { sentFrames } }
    var texts: [String] { lock.withLock { sentTexts } }
    var isClosed: Bool { lock.withLock { closed } }

    func commands(_ name: String) -> [JSONValue] {
        frames.filter { $0["command"]?.string == name }
    }

    var commandNames: [String] {
        frames.compactMap { $0["command"]?.string }
    }

    func send(_ text: String) async throws {
        let (isClosed, reply): (Bool, JSONValue?) = lock.withLock {
            guard !closed else { return (true, nil) }
            sentTexts.append(text)
            guard let frame = JSONValue.parse(text) else { return (false, nil) }
            sentFrames.append(frame)
            guard let command = frame["command"]?.string, let number = frame["sequence"]?.int,
                  !silent.contains(command)
            else { return (false, nil) }
            if let error = errors[command] {
                return (false, ["type": "error", "sequence": .int(number), "error": .string(error)])
            }
            return (false, ["type": "response", "sequence": .int(number), "response": .string(command)])
        }
        if isClosed { throw Ws2Error.closed }
        if let reply { deliver(reply) }
    }

    func receive() async throws -> String {
        let next: String? = await withCheckedContinuation { continuation in
            let ready: (String?, Bool) = lock.withLock {
                if !queue.isEmpty { return (queue.removeFirst(), true) }
                if closed { return (nil, true) }
                waiter = continuation
                return (nil, false)
            }
            if ready.1 { continuation.resume(returning: ready.0) }
        }
        guard let next else { throw Ws2Error.closed }
        return next
    }

    func close() {
        let waiting: CheckedContinuation<String?, Never>? = lock.withLock {
            closed = true
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume(returning: nil)
    }

    func deliver(_ value: JSONValue) {
        deliver(text: value.serialized())
    }

    func deliver(text: String) {
        let waiting: CheckedContinuation<String?, Never>? = lock.withLock {
            guard !closed else { return nil }
            if let waiter {
                self.waiter = nil
                return waiter
            }
            queue.append(text)
            return nil
        }
        waiting?.resume(returning: text)
    }

    /// Уведомление сервера.
    func notify(_ name: String, _ body: [String: JSONValue] = [:]) {
        var message = body
        message["notification"] = .string(name)
        message["type"] = "notification"
        deliver(.object(message))
    }
}

/// Подключения к фейковым серверам по порядку: первое — первому серверу и т. д.
final class FakeConnector: @unchecked Sendable {
    private let lock = NSLock()
    private var servers: [FakeWs2Server]
    private(set) var urls: [URL] = []
    var failures = 0

    init(_ servers: [FakeWs2Server]) {
        self.servers = servers
    }

    var connector: Ws2Connector {
        { url in try self.connect(url) }
    }

    var connections: Int { lock.withLock { urls.count } }

    private func connect(_ url: URL) throws -> any Ws2Socket {
        try lock.withLock {
            urls.append(url)
            if failures > 0 {
                failures -= 1
                throw Ws2Error.closed
            }
            guard !servers.isEmpty else { throw Ws2Error.closed }
            return servers.removeFirst()
        }
    }
}

@MainActor
final class FakeCallPeer: CallPeer {
    var onEvent: ((PeerEvent) -> Void)?
    var signalingState: PeerSignalingState = .stable
    var isGatheringComplete = false
    var localDescription: SessionDescription?
    let iceServers: [CallIceServer]

    var microphone = false
    var receivers = 0
    var sending: [LocalVideo] = []
    var stopped: [LocalVideo] = []
    var slots: [(mids: Set<String>, video: LocalVideo)] = []
    /// Что сейчас в слоте SFU: последнее `fillVideoSlot`, пока его не сняли `stopVideo`.
    var slotVideo: LocalVideo?
    var offers: [Bool] = []
    var locals: [SessionDescription] = []
    var remotes: [SessionDescription] = []
    var candidates: [IceCandidate] = []
    var tracks: [RemoteTrack] = []
    var channels: [FakeCallChannel] = []
    var levels: (local: Double, remote: Double)?
    var closed = false
    var offerSdp = "v=0\r\na=msid:stream cam-track\r\na=ssrc:11 msid:stream cam-track\r\n"
    var answerSdp = "v=0\r\na=msid:stream cam-track\r\n"

    init(iceServers: [CallIceServer]) {
        self.iceServers = iceServers
    }

    func addMicrophone() { microphone = true }
    func addVideoReceiver() { receivers += 1 }

    func sendVideo(_ video: LocalVideo) -> Bool {
        let added = !sending.contains(video)
        sending.append(video)
        return added
    }

    func stopVideo(_ video: LocalVideo) {
        stopped.append(video)
        if slotVideo == video { slotVideo = nil }
    }

    func fillVideoSlot(mids: Set<String>, with video: LocalVideo) -> Bool {
        slots.append((mids, video))
        guard !mids.isEmpty else { return false }
        slotVideo = video
        return true
    }

    func makeOffer(iceRestart: Bool) async throws -> SessionDescription {
        offers.append(iceRestart)
        return SessionDescription(type: .offer, sdp: offerSdp)
    }

    func makeAnswer() async throws -> SessionDescription {
        SessionDescription(type: .answer, sdp: answerSdp)
    }

    func setLocal(_ description: SessionDescription) async throws {
        locals.append(description)
        switch description.type {
        case .offer: signalingState = .haveLocalOffer
        case .answer, .pranswer, .rollback: signalingState = .stable
        }
        if description.type != .rollback { localDescription = description }
    }

    func setRemote(_ description: SessionDescription) async throws {
        remotes.append(description)
        signalingState = description.type == .offer ? .haveRemoteOffer : .stable
    }

    func add(_ candidate: IceCandidate) async { candidates.append(candidate) }
    func remoteTracks() -> [RemoteTrack] { tracks }

    func openChannel(label: String) -> (any CallDataChannel)? {
        let channel = FakeCallChannel(label: label)
        channels.append(channel)
        return channel
    }

    func audioLevels() async -> (local: Double, remote: Double)? { levels }
    func close() { closed = true }

    func emit(_ event: PeerEvent) { onEvent?(event) }
}

@MainActor
final class FakeCallChannel: CallDataChannel {
    let label: String
    var isOpen = false
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var sent: [Data] = []
    var closed = false

    init(label: String) {
        self.label = label
    }

    func send(_ data: Data) -> Bool {
        guard isOpen else { return false }
        sent.append(data)
        return true
    }

    func close() { closed = true }

    func open() {
        isOpen = true
        onOpen?()
    }
}

@MainActor
final class FakeCallMedia: CallMedia {
    var peers: [FakeCallPeer] = []
    var camera: CallCameraPosition?
    var cameraStarts: [CallCameraPosition] = []
    var screen = false
    var microphone = true
    var speaker = false
    var shutDown = false
    var cameraError: CallMediaError?

    var peer: FakeCallPeer? { peers.last }

    func makePeer(iceServers: [CallIceServer]) -> (any CallPeer)? {
        let peer = FakeCallPeer(iceServers: iceServers)
        peers.append(peer)
        return peer
    }

    func trackId(of video: LocalVideo) -> String? {
        switch video {
        case .camera: camera == nil ? nil : "cam-track"
        case .screen: screen ? "screen-track" : nil
        }
    }

    func startCamera(_ position: CallCameraPosition) async throws(CallMediaError) {
        if let cameraError { throw cameraError }
        camera = position
        cameraStarts.append(position)
    }

    func stopCamera() { camera = nil }
    func startScreen() async throws(CallMediaError) { screen = true }
    func stopScreen() { screen = false }
    func setMicrophone(enabled: Bool) { microphone = enabled }
    func setSpeaker(_ on: Bool) { speaker = on }
    func shutdown() { shutDown = true }
}

/// Ждёт условие на главном акторе, отпуская его между проверками.
@MainActor
func settle(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}
