import Foundation
import OrbitleDomain

// Sendable-записи, в которых данные ходят между сервером, очередью и базой.
// Поля совпадают с доменными моделями `Chat` и `Message`. Отдельные типы нужны,
// чтобы формат серверного ответа можно было менять, не трогая домен.

public struct ChatRecord: Sendable, Hashable {
    public var id: String
    public var title: String
    public var type: ChatType
    public var lastMessageId: String?
    public var unreadCount: Int
    public var updatedAt: Date
    public var preview: String?
    // Поля ниже сервер присылает не всегда. `nil` значит «неизвестно», и слияние
    // оставляет то, что уже лежит в базе.
    /// Автор последнего сообщения.
    public var lastAuthorId: String?
    public var avatarURL: URL?
    public var isMuted: Bool?
    public var isArchived: Bool?
    public var isBot: Bool?
    public var isVerified: Bool?
    /// Порядок закреплённых с сервера. Учитывается, только если `pinsKnown`.
    public var pinOrder: Int?
    /// Сервер прислал закреплённые: тогда `pinOrder == nil` значит «не закреплён».
    public var pinsKnown: Bool

    public init(
        id: String,
        title: String,
        type: ChatType,
        lastMessageId: String? = nil,
        unreadCount: Int = 0,
        updatedAt: Date,
        preview: String? = nil,
        lastAuthorId: String? = nil,
        avatarURL: URL? = nil,
        isMuted: Bool? = nil,
        isArchived: Bool? = nil,
        isBot: Bool? = nil,
        isVerified: Bool? = nil,
        pinOrder: Int? = nil,
        pinsKnown: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
        self.preview = preview
        self.lastAuthorId = lastAuthorId
        self.avatarURL = avatarURL
        self.isMuted = isMuted
        self.isArchived = isArchived
        self.isBot = isBot
        self.isVerified = isVerified
        self.pinOrder = pinOrder
        self.pinsKnown = pinsKnown
    }

    public init(_ chat: Chat) {
        self.init(
            id: chat.id,
            title: chat.title,
            type: chat.type,
            lastMessageId: chat.lastMessageId,
            unreadCount: chat.unreadCount,
            updatedAt: chat.updatedAt,
            preview: chat.preview,
            lastAuthorId: chat.lastMessage?.authorId,
            avatarURL: chat.avatarURL,
            isMuted: chat.isMuted,
            isArchived: chat.isArchived,
            isBot: chat.isBot,
            isVerified: chat.isVerified
        )
    }

    public var domain: Chat {
        Chat(
            id: id,
            title: title,
            type: type,
            lastMessageId: lastMessageId,
            unreadCount: unreadCount,
            updatedAt: updatedAt,
            preview: preview,
            lastMessage: lastAuthorId.map { ChatLastMessage(authorId: $0) },
            avatarURL: avatarURL,
            pinOrder: pinsKnown ? pinOrder : nil,
            isMuted: isMuted ?? false,
            isArchived: isArchived ?? false,
            isBot: isBot ?? false,
            isVerified: isVerified ?? false
        )
    }
}

public struct MessageRecord: Sendable, Hashable {
    public var id: String
    public var serverId: String?
    public var chatId: String
    public var authorId: String
    public var text: String
    public var timestamp: Date
    public var status: MessageStatus
    public var mediaId: String?

    public init(id: String, serverId: String? = nil, chatId: String, authorId: String, text: String, timestamp: Date, status: MessageStatus, mediaId: String? = nil) {
        self.id = id
        self.serverId = serverId
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.mediaId = mediaId
    }

    public init(_ message: Message) {
        self.init(id: message.id, serverId: message.serverId, chatId: message.chatId, authorId: message.authorId, text: message.text, timestamp: message.timestamp, status: message.status, mediaId: message.mediaId)
    }

    public var domain: Message {
        Message(id: id, serverId: serverId, chatId: chatId, authorId: authorId, text: text, timestamp: timestamp, status: status, mediaId: mediaId)
    }
}
