import Foundation
import OrbitlDomain

/// Ошибки серверных вызовов.
public enum MaxAPIError: Error, Sendable, Equatable {
    /// Реальный вызов ещё не реализован.
    case notImplemented
    /// Нет сети или соединение с сервером потеряно.
    case offline
    /// Сервер вернул ошибку с кодом.
    case server(code: String)
    /// Ответ не удалось разобрать.
    case invalidResponse

    /// Имеет ли смысл повторить запрос позже.
    public var isRetryable: Bool {
        switch self {
        case .offline, .server: true
        case .notImplemented, .invalidResponse: false
        }
    }

    /// Категория ошибки для UI (architecture.md, «Ошибки и офлайн»).
    public var orbitlError: OrbitlError {
        switch self {
        case .offline: .offline
        case .server(let code): .server(code: code)
        case .invalidResponse: .invalidRequest
        case .notImplemented: .unknown
        }
    }
}

/// Ответ сервера на отправку сообщения.
public struct SentMessage: Sendable, Hashable {
    public var serverId: String
    public var timestamp: Date

    public init(serverId: String, timestamp: Date) {
        self.serverId = serverId
        self.timestamp = timestamp
    }
}

/// Серверные вызовы, которые нужны репозиториям. Протокол, чтобы в тестах
/// подставлять фейковую реализацию.
public protocol MaxAPI: Sendable {
    func fetchChats() async -> Result<[ChatRecord], MaxAPIError>
    /// Сообщения чата строго старше `before` (самые новые, если `nil`), не больше `limit`.
    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// `clientId` это локальный id сообщения, нужен серверу для защиты от дублей при повторе.
    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError>
    func markRead(chatId: String) async -> Result<Void, MaxAPIError>
}

/// Клиент API Max поверх ядра max-kmp-core.
///
/// Пока это заглушки, которые возвращают `.failure(.notImplemented)`.
// TODO: реализовать через KMPCoreBridge (протокол ядра) и URLSessionClient
// (HTTP вне протокола), переводя MaxError ядра в MaxAPIError.
public final class MaxAPIClient: MaxAPI {
    public init() {}

    public func fetchChats() async -> Result<[ChatRecord], MaxAPIError> {
        // TODO: запрос списка чатов через ядро.
        .failure(.notImplemented)
    }

    public func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        // TODO: запрос истории чата через ядро.
        .failure(.notImplemented)
    }

    public func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        // TODO: отправка сообщения через ядро.
        .failure(.notImplemented)
    }

    public func markRead(chatId: String) async -> Result<Void, MaxAPIError> {
        // TODO: отметка о прочтении через ядро.
        .failure(.notImplemented)
    }
}
