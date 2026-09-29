import Foundation

// Sendable-снимки записей. Модели SwiftData не Sendable и не выходят за пределы
// своего контекста, поэтому SyncEngine передаёт данные с сервера в репозитории
// в виде этих структур.

public struct ChatRecord: Sendable, Hashable {
    public var id: String
    public var title: String
    public var kind: ChatKind
    public var lastMessageId: String?
    public var unreadCount: Int
    public var updatedAt: Date

    public init(id: String, title: String, kind: ChatKind, lastMessageId: String?, unreadCount: Int, updatedAt: Date) {
        self.id = id
        self.title = title
        self.kind = kind
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }
}

public struct MessageRecord: Sendable, Hashable {
    public var id: String
    public var chatId: String
    public var authorId: String
    public var text: String
    public var timestamp: Date
    public var status: MessageStatus
    public var mediaId: String?

    public init(id: String, chatId: String, authorId: String, text: String, timestamp: Date, status: MessageStatus, mediaId: String?) {
        self.id = id
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.mediaId = mediaId
    }
}
