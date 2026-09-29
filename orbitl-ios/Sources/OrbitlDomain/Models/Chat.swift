import Foundation

/// Тип чата.
public enum ChatType: String, Codable, Hashable, Sendable {
    /// Личная переписка один на один.
    case `private`
    case group
}

/// Чат, как его видит UI.
public struct Chat: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var type: ChatType
    public var lastMessageId: String?
    public var unreadCount: Int
    /// Время последней активности, по нему сортируется список чатов.
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        type: ChatType,
        lastMessageId: String? = nil,
        unreadCount: Int = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }
}
