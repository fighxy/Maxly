import Foundation
@preconcurrency import WebRTC
import MaxlyData
import MaxlyDomain

/// Значение, которое WebRTC отдаёт со своего потока, а нужно на главном.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}

enum WebRTCFailure: Error {
    case noDescription
}

/// Соединение WebRTC (`RTCPeerConnection`) за протоколом `CallPeer`.
@MainActor
final class WebRTCPeer: CallPeer {
    var onEvent: ((PeerEvent) -> Void)?

    private let connection: RTCPeerConnection
    private let bridge: PeerBridge
    private weak var media: WebRTCCallMedia?
    private var senders: [LocalVideo: RTCRtpSender] = [:]
    private var channels: [WebRTCDataChannel] = []
    private var closed = false

    init?(factory: RTCPeerConnectionFactory, iceServers: [CallIceServer], media: WebRTCCallMedia) {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.tcpCandidatePolicy = .enabled
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.audioJitterBufferMaxPackets = 200
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        let bridge = PeerBridge()
        guard let connection = factory.peerConnection(with: configuration, constraints: constraints, delegate: bridge) else {
            return nil
        }
        self.connection = connection
        self.bridge = bridge
        self.media = media
        bridge.owner = self
    }

    var signalingState: PeerSignalingState {
        switch connection.signalingState {
        case .stable: .stable
        case .haveLocalOffer: .haveLocalOffer
        case .haveRemoteOffer: .haveRemoteOffer
        case .closed: .closed
        default: .other
        }
    }

    var isGatheringComplete: Bool {
        connection.iceGatheringState == .complete
    }

    var localDescription: SessionDescription? {
        connection.localDescription.map(Self.session)
    }

    func addMicrophone() {
        guard let track = media?.audioTrack else { return }
        _ = connection.add(track, streamIds: [WebRTCCallMedia.streamId])
    }

    func addVideoReceiver() {
        let initial = RTCRtpTransceiverInit()
        initial.direction = .recvOnly
        _ = connection.addTransceiver(of: .video, init: initial)
    }

    func sendVideo(_ video: LocalVideo) -> Bool {
        guard let track = media?.videoTrack(video) else { return false }
        if let sender = senders[video] {
            sender.track = track
            return false
        }
        guard let sender = connection.add(track, streamIds: [WebRTCCallMedia.streamId]) else { return false }
        senders[video] = sender
        return true
    }

    func stopVideo(_ video: LocalVideo) {
        senders[video]?.track = nil
    }

    @discardableResult
    func fillVideoSlot(mids: Set<String>, with video: LocalVideo) -> Bool {
        guard let track = media?.videoTrack(video) else { return false }
        for transceiver in connection.transceivers where transceiver.mediaType == .video && mids.contains(transceiver.mid) {
            let sender = transceiver.sender
            sender.track = track
            transceiver.setDirection(.sendOnly, error: nil)
            // Слот один: камера и экран сменяют друг друга в одном отправителе. Прежнее видео
            // больше не держит его, иначе его `stopVideo` снял бы из слота новое.
            let slotId = sender.senderId
            for (other, known) in senders where other != video && known.senderId == slotId {
                senders[other] = nil
            }
            senders[video] = sender
            return true
        }
        return false
    }

    func makeOffer(iceRestart: Bool) async throws -> SessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: iceRestart ? [kRTCMediaConstraintsIceRestart: kRTCMediaConstraintsValueTrue] : nil,
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            connection.offer(for: constraints) { @Sendable description, error in
                if let description {
                    continuation.resume(returning: Self.session(description))
                } else {
                    continuation.resume(throwing: error ?? WebRTCFailure.noDescription)
                }
            }
        }
    }

    func makeAnswer() async throws -> SessionDescription {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return try await withCheckedThrowingContinuation { continuation in
            connection.answer(for: constraints) { @Sendable description, error in
                if let description {
                    continuation.resume(returning: Self.session(description))
                } else {
                    continuation.resume(throwing: error ?? WebRTCFailure.noDescription)
                }
            }
        }
    }

    func setLocal(_ description: SessionDescription) async throws {
        let value = Self.rtc(description)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.setLocalDescription(value) { @Sendable error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemote(_ description: SessionDescription) async throws {
        let value = Self.rtc(description)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.setRemoteDescription(value) { @Sendable error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func add(_ candidate: IceCandidate) async {
        let value = RTCIceCandidate(sdp: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.add(value) { @Sendable _ in
                continuation.resume()
            }
        }
    }

    /// Дорожки приёмников, которые по согласованному SDP действительно принимают: слот приёма,
    /// на который собеседник ничего не шлёт, видео не даст.
    func remoteTracks() -> [RemoteTrack] {
        connection.transceivers.compactMap { transceiver in
            var direction = RTCRtpTransceiverDirection.inactive
            guard transceiver.currentDirection(&direction),
                  direction == .sendRecv || direction == .recvOnly,
                  let track = transceiver.receiver.track
            else { return nil }
            return register(track)
        }
    }

    func openChannel(label: String) -> (any CallDataChannel)? {
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = true
        guard let channel = connection.dataChannel(forLabel: label, configuration: configuration) else { return nil }
        let wrapper = WebRTCDataChannel(channel)
        channels.append(wrapper)
        return wrapper
    }

    func audioLevels() async -> (local: Double, remote: Double)? {
        guard !closed else { return nil }
        let levels: Unchecked<(Double, Double)> = await withCheckedContinuation { continuation in
            connection.statistics { @Sendable report in
                var local = 0.0
                var remote = 0.0
                for statistic in report.statistics.values {
                    let values = statistic.values
                    guard (values["kind"] as? String) == "audio" || (values["mediaType"] as? String) == "audio",
                          let level = (values["audioLevel"] as? NSNumber)?.doubleValue
                    else { continue }
                    if statistic.type == "media-source" {
                        local = max(local, level)
                    } else if statistic.type == "inbound-rtp" {
                        remote = max(remote, level)
                    }
                }
                continuation.resume(returning: Unchecked(value: (local, remote)))
            }
        }
        return (levels.value.0, levels.value.1)
    }

    func close() {
        guard !closed else { return }
        closed = true
        onEvent = nil
        bridge.owner = nil
        channels.forEach { $0.close() }
        channels = []
        senders = [:]
        connection.close()
    }

    // MARK: События с потока WebRTC

    func receive(_ event: PeerEvent) {
        guard !closed else { return }
        onEvent?(event)
    }

    func receive(track: RTCMediaStreamTrack) {
        guard !closed, let remote = register(track) else { return }
        onEvent?(.remoteTrack(remote))
    }

    private func register(_ track: RTCMediaStreamTrack) -> RemoteTrack? {
        let kind: MediaKind = track.kind == kRTCMediaStreamTrackKindVideo ? .video : .audio
        if let video = track as? RTCVideoTrack {
            CallVideoRegistry.shared.register(video)
        }
        return RemoteTrack(id: track.trackId, kind: kind)
    }

    private nonisolated static func session(_ value: RTCSessionDescription) -> SessionDescription {
        let type: SdpType = switch value.type {
        case .offer: .offer
        case .answer: .answer
        case .prAnswer: .pranswer
        case .rollback: .rollback
        @unknown default: .offer
        }
        return SessionDescription(type: type, sdp: value.sdp)
    }

    private static func rtc(_ description: SessionDescription) -> RTCSessionDescription {
        let type: RTCSdpType = switch description.type {
        case .offer: .offer
        case .answer: .answer
        case .pranswer: .prAnswer
        case .rollback: .rollback
        }
        return RTCSessionDescription(type: type, sdp: description.sdp)
    }
}

/// Делегат `RTCPeerConnection`: WebRTC зовёт его со своего потока, события уходят на главный
/// по порядку.
final class PeerBridge: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private weak var _owner: WebRTCPeer?

    var owner: WebRTCPeer? {
        get { lock.withLock { _owner } }
        set { lock.withLock { _owner = newValue } }
    }

    private func send(_ event: PeerEvent) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.owner?.receive(event)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .failed { send(.iceFailed) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete { send(.gatheringComplete) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        send(.candidate(IceCandidate(sdp: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        let state: PeerState = switch newState {
        case .new: .new
        case .connecting: .connecting
        case .connected: .connected
        case .disconnected: .disconnected
        case .failed: .failed
        case .closed: .closed
        @unknown default: .new
        }
        send(.state(state))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if let track = transceiver.receiver.track { send(track: track) }
    }

    private func send(track: RTCMediaStreamTrack) {
        let box = Unchecked(value: track)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.owner?.receive(track: box.value)
            }
        }
    }
}

/// Канал данных WebRTC за протоколом `CallDataChannel`.
@MainActor
final class WebRTCDataChannel: CallDataChannel {
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?

    private let channel: RTCDataChannel
    private let bridge: ChannelBridge

    init(_ channel: RTCDataChannel) {
        self.channel = channel
        bridge = ChannelBridge()
        bridge.owner = self
        channel.delegate = bridge
    }

    var label: String { channel.label }
    var isOpen: Bool { channel.readyState == .open }

    @discardableResult
    func send(_ data: Data) -> Bool {
        guard isOpen else { return false }
        return channel.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

    func close() {
        bridge.owner = nil
        channel.delegate = nil
        channel.close()
    }

    func opened() {
        if isOpen { onOpen?() }
    }

    func received(_ data: Data) {
        onMessage?(data)
    }
}

final class ChannelBridge: NSObject, RTCDataChannelDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private weak var _owner: WebRTCDataChannel?

    var owner: WebRTCDataChannel? {
        get { lock.withLock { _owner } }
        set { lock.withLock { _owner = newValue } }
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.owner?.opened()
            }
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard buffer.isBinary else { return }
        let data = buffer.data
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.owner?.received(data)
            }
        }
    }
}
