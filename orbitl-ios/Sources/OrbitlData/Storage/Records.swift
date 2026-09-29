import Foundation
import OrbitlDomain

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

    public init(id: String, title: String, type: ChatType, lastMessageId: String? = nil, unreadCount: Int = 0, updatedAt: Date) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }

    public init(_ chat: Chat) {
        self.init(id: chat.id, title: chat.title, type: chat.type, lastMessageId: chat.lastMessageId, unreadCount: chat.unreadCount, updatedAt: chat.updatedAt)
    }

    public var domain: Chat {
        Chat(id: id, title: title, type: type, lastMessageId: lastMessageId, unreadCount: unreadCount, updatedAt: updatedAt)
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
