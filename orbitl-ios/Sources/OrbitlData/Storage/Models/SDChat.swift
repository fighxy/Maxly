import Foundation
import SwiftData

/// Тип чата в Max.
public enum ChatKind: String, Codable, Sendable {
    case dialog
    case group
    case channel
}

/// Чат в локальной базе.
@Model
final class SDChat {
    @Attribute(.unique) var id: String
    var title: String
    var kindRaw: String
    var lastMessageId: String?
    var unreadCount: Int
    /// Время последней активности, по нему сортируется список чатов.
    var updatedAt: Date

    /// Сообщения чата. При удалении чата удаляются вместе с ним.
    @Relationship(deleteRule: .cascade, inverse: \SDMessage.chat)
    var messages: [SDMessage] = []

    var kind: ChatKind {
        get { ChatKind(rawValue: kindRaw) ?? .dialog }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: String,
        title: String,
        kind: ChatKind,
        lastMessageId: String? = nil,
        unreadCount: Int = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }
}
