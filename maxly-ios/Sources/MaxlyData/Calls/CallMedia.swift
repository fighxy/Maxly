import Foundation
import MaxlyDomain

/// Тип описания сессии WebRTC.
public enum SdpType: String, Hashable, Sendable {
    case offer, answer, pranswer, rollback
}

/// Описание сессии (SDP) с типом.
public struct SessionDescription: Hashable, Sendable {
    public var type: SdpType
    public var sdp: String

    public init(type: SdpType, sdp: String) {
        self.type = type
        self.sdp = sdp
    }
}

/// Кандидат ICE.
public struct IceCandidate: Hashable, Sendable {
    public var sdp: String
    public var sdpMid: String?
    public var sdpMLineIndex: Int32

    public init(sdp: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.sdp = sdp
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

/// Состояние согласования SDP.
public enum PeerSignalingState: Hashable, Sendable {
    case stable, haveLocalOffer, haveRemoteOffer, other, closed
}

/// Состояние соединения WebRTC.
public enum PeerState: Hashable, Sendable {
    case new, connecting, connected, disconnected, failed, closed
}

public enum MediaKind: String, Hashable, Sendable {
    case audio, video
}

/// Дорожка собеседника: id и вид.
public struct RemoteTrack: Hashable, Sendable {
    public var id: String
    public var kind: MediaKind

    public init(id: String, kind: MediaKind) {
        self.id = id
        self.kind = kind
    }
}

/// Своё видео: камера или экран.
public enum LocalVideo: String, Hashable, Sendable, CaseIterable {
    case camera, screen
}

/// Событие соединения WebRTC. Приходит на главном потоке.
public enum PeerEvent: Sendable {
    case candidate(IceCandidate)
    case gatheringComplete
    case state(PeerState)
    /// ICE не нашёл путь. В SFU после этого просят у сервера новый (`request-realloc`).
    case iceFailed
    case remoteTrack(RemoteTrack)
}

/// Соединение WebRTC с собеседником или с SFU сервера. Всё на главном потоке.
@MainActor
public protocol CallPeer: AnyObject {
    var onEvent: ((PeerEvent) -> Void)? { get set }
    var signalingState: PeerSignalingState { get }
    var isGatheringComplete: Bool { get }
    var localDescription: SessionDescription? { get }
    /// Отправлять микрофон.
    func addMicrophone()
    /// Слот только на приём видео (`recvonly`).
    func addVideoReceiver()
    /// Начать отправлять видео. `true` — появился новый отправитель, без нового SDP его не увидят.
    func sendVideo(_ video: LocalVideo) -> Bool
    /// Перестать отправлять видео: отправитель остаётся, но без дорожки.
    func stopVideo(_ video: LocalVideo)
    /// SFU: отдать видео в слот, который сервер предложил приёмом (`a=recvonly`) с этими `mid`.
    /// Повторный вызов меняет дорожку в том же отправителе слота: нового отправителя нет.
    @discardableResult
    func fillVideoSlot(mids: Set<String>, with video: LocalVideo) -> Bool
    func makeOffer(iceRestart: Bool) async throws -> SessionDescription
    func makeAnswer() async throws -> SessionDescription
    func setLocal(_ description: SessionDescription) async throws
    func setRemote(_ description: SessionDescription) async throws
    /// Кандидат собеседника. Ошибку WebRTC глотает: битый кандидат не рвёт звонок.
    func add(_ candidate: IceCandidate) async
    /// Дорожки всех приёмников.
    func remoteTracks() -> [RemoteTrack]
    func openChannel(label: String) -> (any CallDataChannel)?
    /// Уровни звука 0…1: своего микрофона и самого громкого входящего; `nil`, если статистики нет.
    func audioLevels() async -> (local: Double, remote: Double)?
    func close()
}

/// Канал данных WebRTC. Всё на главном потоке.
@MainActor
public protocol CallDataChannel: AnyObject {
    var label: String { get }
    var isOpen: Bool { get }
    var onOpen: (() -> Void)? { get set }
    var onMessage: ((Data) -> Void)? { get set }
    @discardableResult
    func send(_ data: Data) -> Bool
    func close()
}

public enum CallMediaError: Error, Equatable, Sendable {
    /// Нет разрешения на микрофон, камеру или запись экрана.
    case denied
    /// Устройство недоступно.
    case unavailable
}

/// Свои микрофон, камера и экран, и фабрика соединений. Один на звонок.
@MainActor
public protocol CallMedia: AnyObject {
    func makePeer(iceServers: [CallIceServer]) -> (any CallPeer)?
    /// Id дорожки своего видео: по нему SDP подписывается `u<id>:sCAMERA` / `u<id>:sSCREEN`.
    func trackId(of video: LocalVideo) -> String?
    func startCamera(_ position: CallCameraPosition) async throws(CallMediaError)
    func stopCamera()
    func startScreen() async throws(CallMediaError)
    func stopScreen()
    func setMicrophone(enabled: Bool)
    func setSpeaker(_ on: Bool)
    /// Звонок закончился: остановить захват и освободить всё.
    func shutdown()
}
