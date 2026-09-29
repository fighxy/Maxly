import Foundation

/// Фаза `MaxClient`, как её отдаёт iOS-фасад ядра.
public enum CorePhase: String, Sendable, Equatable {
    case idle
    case connecting
    case awaitingAuth
    case ready
    case reconnecting
    case tokenRejected
    case failed

    public init(raw: String) {
        self = CorePhase(rawValue: raw) ?? .failed
    }
}

/// Классифицированная ошибка ядра. `kind` совпадает с `ErrorKind` (`NETWORK`, `SESSION_EXPIRED`, …).
public struct CoreFailure: Error, Sendable, Equatable {
    public var kind: String
    public var key: String?

    public init(kind: String, key: String?) {
        self.kind = kind
        self.key = key.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct CoreCode: Sendable, Equatable {
    public var token: String
    public var codeLength: Int?

    public init(token: String, codeLength: Int?) {
        self.token = token
        self.codeLength = codeLength
    }
}

public enum CoreAuthStep: Sendable, Equatable {
    case loggedIn(userId: String)
    case password(trackId: String, hint: String?)
    case register(token: String)
}

public struct CoreChat: Sendable, Equatable {
    public var id: String
    public var title: String
    public var type: String
    public var lastMessageId: String
    public var lastText: String
    public var updatedAtMs: Int64
    public var unread: Int

    public init(id: String, title: String, type: String, lastMessageId: String, lastText: String, updatedAtMs: Int64, unread: Int) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.lastText = lastText
        self.updatedAtMs = updatedAtMs
        self.unread = unread
    }
}

public struct CoreMessage: Sendable, Equatable {
    public var id: String
    public var chatId: String
    public var authorId: String
    public var text: String
    public var timeMs: Int64

    public init(id: String, chatId: String, authorId: String, text: String, timeMs: Int64) {
        self.id = id
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timeMs = timeMs
    }
}

/// Пуш, который клиент пишет в базу. Звонки, присутствие и неизвестные опкоды сюда не входят.
public struct CoreEvent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case message
        case edited
        case deleted
        case chat
        case typing
        case read
    }

    public var kind: Kind
    public var chatId: String
    public var messageId: String
    public var authorId: String
    public var text: String
    public var title: String
    public var chatType: String
    public var timeMs: Int64
    /// `-1`, если событие не меняет счётчик непрочитанных.
    public var unread: Int

    public init(kind: Kind, chatId: String, messageId: String, authorId: String, text: String, title: String, chatType: String, timeMs: Int64, unread: Int) {
        self.kind = kind
        self.chatId = chatId
        self.messageId = messageId
        self.authorId = authorId
        self.text = text
        self.title = title
        self.chatType = chatType
        self.timeMs = timeMs
        self.unread = unread
    }
}

/// Узкий вход в max-kmp-core. Реализация с `import MaxIos` живёт в приложении, тесты подставляют фейк.
public protocol MaxCore: Sendable {
    func phaseName() async -> CorePhase
    func currentUserId() async -> String
    func hasStoredToken() async -> Bool
    func start() async throws -> CorePhase
    func requestCode(phone: String, resend: Bool) async throws -> CoreCode
    func verifyCode(token: String, code: String) async throws -> CoreAuthStep
    func checkPassword(trackId: String, password: String) async throws -> CoreAuthStep
    func register(token: String, firstName: String, lastName: String) async throws -> CoreAuthStep
    func logout() async throws
    func loadChats() async throws -> [CoreChat]
    func loadChat(id: String) async throws -> CoreChat
    func loadHistory(chatId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage]
    func sendText(chatId: String, text: String) async throws -> CoreMessage
    func markRead(chatId: String, messageId: String) async throws
    func phases() -> AsyncStream<CorePhase>
    func events() -> AsyncStream<CoreEvent>
}
