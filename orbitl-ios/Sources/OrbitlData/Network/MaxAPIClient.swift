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
    /// Сохранённый токен больше не действует.
    case sessionExpired
    /// Ввод отклонён, например неверный пароль.
    case rejected(String)
    /// Ответ не удалось разобрать.
    case invalidResponse

    /// Имеет ли смысл повторить запрос позже.
    public var isRetryable: Bool {
        switch self {
        case .offline, .server: true
        case .notImplemented, .invalidResponse, .sessionExpired, .rejected: false
        }
    }

    /// Категория ошибки для UI (architecture.md, «Ошибки и офлайн»).
    public var orbitlError: OrbitlError {
        switch self {
        case .offline: .networkUnavailable
        case .server(let code): .server(code: code)
        case .sessionExpired: .authExpired
        case .rejected(let message): .rejected(message)
        case .invalidResponse: .invalidRequest
        case .notImplemented: .syncFailed
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
    /// Один чат. Ошибка, если сервер его не вернул.
    func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError>
    /// Сообщения чата строго старше `before` (самые новые, если `nil`), не больше `limit`.
    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// `clientId` это локальный id. Ядро само ставит числовой `cid` в пакет, локальный id на сервер не уходит.
    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError>
    /// `messageId` nil значит, что локально нечего отмечать: сервер не вызывается.
    func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError>
}

/// Клиент API Max поверх `MaxCore`. Типы Kotlin сюда не попадают.
public final class MaxAPIClient: MaxAPI, Sendable {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func fetchChats() async -> Result<[ChatRecord], MaxAPIError> {
        await catching {
            try await core.loadChats().map(CoreMapping.chat)
        }
    }

    public func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError> {
        await catching {
            try CoreMapping.chat(await core.loadChat(id: id))
        }
    }

    public func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadHistory(chatId: chatId, beforeMs: before?.unixMillis ?? 0, limit: limit)
            return page.map(CoreMapping.message)
        }
    }

    public func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        _ = clientId
        return await catching {
            let sent = try await core.sendText(chatId: chatId, text: text)
            return SentMessage(serverId: sent.id, timestamp: Date(unixMillis: sent.timeMs))
        }
    }

    public func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError> {
        guard let messageId, !messageId.isEmpty else { return .success(()) }
        return await catching {
            try await core.markRead(chatId: chatId, messageId: messageId)
        }
    }

    private func catching<T>(_ body: () async throws -> T) async -> Result<T, MaxAPIError> {
        do {
            return .success(try await body())
        } catch {
            return .failure(CoreMapping.apiError(error))
        }
    }
}
