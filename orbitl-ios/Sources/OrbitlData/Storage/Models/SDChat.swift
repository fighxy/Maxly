import Foundation
import SwiftData
import OrbitlDomain

/// Чат в локальной базе.
@Model
final class SDChat {
    @Attribute(.unique) var id: String
    var title: String
    var typeRaw: String
    var lastMessageId: String?
    var unreadCount: Int
    /// Время последней активности, по нему сортируется список чатов.
    var updatedAt: Date

    /// Сообщения чата. При удалении чата удаляются вместе с ним.
    @Relationship(deleteRule: .cascade, inverse: \SDMessage.chat)
    var messages: [SDMessage] = []

    var type: ChatType {
        get { ChatType(rawValue: typeRaw) ?? .private }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: String,
        title: String,
        type: ChatType,
        lastMessageId: String? = nil,
        unreadCount: Int = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
    }
}
