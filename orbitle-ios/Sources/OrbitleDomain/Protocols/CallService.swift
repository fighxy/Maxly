import Foundation

/// Звонки через основной сервер Max: начать, войти по ссылке, создать ссылку и слушать входящие.
/// Сам разговор идёт через сервер звонков (`CallControl`).
public protocol CallService: Sendable {
    /// Позвонить пользователю Max. Сервер отвечает адресом ws2, у собеседника начинает звонить.
    func startCall(peerId: String, isVideo: Bool) async throws(OrbitleError) -> CallConnection
    /// Войти в групповой звонок по ссылке `https://max.ru/joincall/…` или её токену.
    func join(link: String, isVideo: Bool) async throws(OrbitleError) -> CallConnection
    /// Новый групповой звонок со ссылкой. Создатель входит в него по этой же ссылке.
    func createLink() async throws(OrbitleError) -> CallLink
    /// Что за звонок за ссылкой; `nil`, если ссылка не ведёт в звонок.
    func preview(link: String) async throws(OrbitleError) -> CallLinkPreview?
    /// Входящие звонки, пока подписка жива.
    func incomingCalls() -> AsyncStream<IncomingCall>
    /// Отклонить входящий через основной сервер (`VIDEO_CHAT_HANGUP` 167, причина `REJECTED`).
    /// Пустой `peerId` не уходит. Ошибка — сервер не принял отбой.
    func reject(conversationId: String, peerId: String) async throws(OrbitleError)
}

public extension CallService {
    func preview(link: String) async throws(OrbitleError) -> CallLinkPreview? { nil }
    /// Источник без отбоя через сервер: входящий отклоняется только в сокете звонка.
    func reject(conversationId: String, peerId: String) async throws(OrbitleError) {}
}

/// Один звонок: подключение к серверу звонков, звук и видео.
@MainActor
public protocol CallControl: AnyObject {
    var state: CallState { get }
    /// Вызывается при каждом изменении `state`.
    var onChange: ((CallState) -> Void)? { get set }
    /// Подключиться к серверу звонков. Входящий до `accept` только слушает: так видно,
    /// что звонящий сбросил.
    func start() async
    /// Ответить на входящий, сразу с камерой или без.
    func accept(video: Bool) async
    /// Положить трубку; у входящего до ответа — отклонить.
    func hangUp() async
    func setMuted(_ muted: Bool) async
    func setCamera(_ on: Bool) async
    func switchCamera() async
    func setScreenSharing(_ on: Bool) async
    func setSpeaker(_ on: Bool)
    /// Запись звонка на сервере. Включать может админ группового звонка.
    func setRecording(_ on: Bool) async
    /// Позвать в идущий звонок пользователей Max.
    func invite(userIds: [String]) async throws(OrbitleError)
}

/// Делает звонки: сигнальный сокет и WebRTC.
@MainActor
public protocol CallEngine: AnyObject {
    func makeCall(connection: CallConnection, role: CallRole, isGroup: Bool) -> any CallControl
}
