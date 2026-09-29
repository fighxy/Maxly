import Foundation
import SwiftData

/// Статус сообщения. `sending` и `failed` бывают только у исходящих.
public enum MessageStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

/// Сообщение в локальной базе.
@Model
final class SDMessage {
    @Attribute(.unique) var id: String
    /// Дублирует `chat?.id`, чтобы фильтровать без обхода связи.
    var chatId: String
    var authorId: String
    var text: String
    /// Время отправки. Используется как курсор пагинации.
    var timestamp: Date
    var statusRaw: String
    var mediaId: String?

    var chat: SDChat?

    /// Вложение. Если медиа удалено, ссылка обнуляется, а сообщение остаётся.
    @Relationship(deleteRule: .nullify)
    var media: SDMediaItem?

    var status: MessageStatus {
        get { MessageStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: String,
        chatId: String,
        authorId: String,
        text: String,
        timestamp: Date,
        status: MessageStatus,
        mediaId: String? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.statusRaw = status.rawValue
        self.mediaId = mediaId
    }
}
