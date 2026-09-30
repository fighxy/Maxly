import Foundation
import SwiftData
import OrbitleDomain

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
    /// Текст последнего сообщения. Сервер может прислать пустую строку, тогда поле nil.
    var preview: String?

    // Поля ниже добавлены позже. У всех есть значение по умолчанию, поэтому SwiftData
    // переносит старую базу без ручной миграции.

    /// Автор последнего сообщения, если известен.
    var lastAuthorId: String?
    /// Последнее сообщение — своё.
    var lastOutgoing: Bool = false
    /// Локальный id своего сообщения, которое строка показывает, пока сервер его не принял.
    var lastLocalId: String?
    /// `DeliveryState` своего последнего сообщения.
    var lastDeliveryRaw: String?
    /// Время (мс) последней отметки прочтения собеседником.
    var peerReadMark: Int64 = 0
    /// Место в закреплённых, `nil` — не закреплён.
    var pinOrder: Int?
    var isMarkedUnread: Bool = false
    var isMuted: Bool = false
    var isArchived: Bool = false
    var isBot: Bool = false
    var isVerified: Bool = false
    var avatarURLString: String?
    var draftText: String?
    var draftAt: Date?
    /// `MessageMediaKind` первого вложения последнего сообщения.
    var lastMediaRaw: String?
    var lastThumbnailURLString: String?
    /// Комментарии канала: `1` включены, `0` выключены, `-1` неизвестно.
    var commentsOption: Int = -1
    /// Можно ли писать: `1` да, `0` нет, `-1` неизвестно.
    var canWriteOption: Int = -1

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
        updatedAt: Date,
        preview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
        self.preview = preview
    }
}
