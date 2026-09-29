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
    /// Картинка чата, у диалога — собеседника. Пусто, если её нет.
    public var avatarURL: String
    /// Автор последнего сообщения. Пусто, если неизвестен.
    public var lastAuthorId: String

    public init(
        id: String, title: String, type: String, lastMessageId: String, lastText: String, updatedAtMs: Int64, unread: Int,
        avatarURL: String = "", lastAuthorId: String = ""
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.lastText = lastText
        self.updatedAtMs = updatedAtMs
        self.unread = unread
        self.avatarURL = avatarURL
        self.lastAuthorId = lastAuthorId
    }
}

/// Контакт из списка аккаунта (`contacts` ответа `LOGIN`).
public struct CoreContact: Sendable, Equatable {
    public var id: String
    public var firstName: String
    public var lastName: String
    /// Цифры без `+`, пусто, если номер скрыт.
    public var phone: String
    public var avatarURL: String
    /// Последний визит, мс Unix; 0 — неизвестно.
    public var lastSeenMs: Int64
    public var online: Bool

    public init(id: String, firstName: String, lastName: String, phone: String, avatarURL: String, lastSeenMs: Int64, online: Bool) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.avatarURL = avatarURL
        self.lastSeenMs = lastSeenMs
        self.online = online
    }
}

/// Карточка чата из ядра (`loadProfile`). Пустые строки и нули — «нет данных».
public struct CoreProfile: Sendable, Equatable {
    public struct Command: Sendable, Equatable {
        public var name: String
        public var description: String

        public init(name: String, description: String) {
            self.name = name
            self.description = description
        }
    }

    /// `user`, `bot`, `group`, `channel` или `saved`.
    public var kind: String
    public var chatId: String
    public var peerId: String
    public var title: String
    public var avatarURL: String
    public var description: String
    public var link: String
    /// Цифры без `+`.
    public var phone: String
    public var participants: Int
    public var lastSeenMs: Int64
    public var online: Bool
    public var official: Bool
    public var isPublic: Bool
    public var commands: [Command]

    public init(
        kind: String, chatId: String, peerId: String = "", title: String = "", avatarURL: String = "",
        description: String = "", link: String = "", phone: String = "", participants: Int = 0,
        lastSeenMs: Int64 = 0, online: Bool = false, official: Bool = false, isPublic: Bool = false,
        commands: [Command] = []
    ) {
        self.kind = kind
        self.chatId = chatId
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
        self.description = description
        self.link = link
        self.phone = phone
        self.participants = participants
        self.lastSeenMs = lastSeenMs
        self.online = online
        self.official = official
        self.isPublic = isPublic
        self.commands = commands
    }
}

/// Звонок из журнала (`VIDEO_CHAT_HISTORY`).
public struct CoreCall: Sendable, Equatable {
    public var id: String
    /// Пусто, если сервер не прислал чат.
    public var chatId: String
    /// Пусто у группового звонка.
    public var peerId: String
    public var title: String
    public var avatarURL: String
    public var isGroup: Bool
    public var outgoing: Bool
    public var missed: Bool
    public var video: Bool
    /// `HUNGUP`, `CANCELED`, `REJECTED`, `MISSED`…
    public var hangupType: String
    /// Длительность как её прислал сервер; 0 — не ответили.
    public var duration: Int64
    public var timeMs: Int64

    public init(
        id: String, chatId: String, peerId: String, title: String, avatarURL: String, isGroup: Bool,
        outgoing: Bool, missed: Bool, video: Bool, hangupType: String, duration: Int64, timeMs: Int64
    ) {
        self.id = id
        self.chatId = chatId
        self.peerId = peerId
        self.title = title
        self.avatarURL = avatarURL
        self.isGroup = isGroup
        self.outgoing = outgoing
        self.missed = missed
        self.video = video
        self.hangupType = hangupType
        self.duration = duration
        self.timeMs = timeMs
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
    func loadContacts() async throws -> [CoreContact]
    func loadCallHistory() async throws -> [CoreCall]
    func loadProfile(chatId: String) async throws -> CoreProfile
}

public extension MaxCore {
    /// Фейки в тестах, которым контакты не нужны.
    func loadContacts() async throws -> [CoreContact] { [] }
    func loadCallHistory() async throws -> [CoreCall] { [] }
    func loadProfile(chatId: String) async throws -> CoreProfile {
        throw CoreFailure(kind: "NOT_FOUND", key: nil)
    }
}
