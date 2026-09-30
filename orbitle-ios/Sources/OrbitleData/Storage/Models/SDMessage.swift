import Foundation
import SwiftData
import OrbitleDomain

/// Сообщение в локальной базе.
@Model
final class SDMessage {
    /// Локальный id. У исходящих это `local-<uuid>` до и после отправки.
    @Attribute(.unique) var id: String
    /// id на сервере. У входящих совпадает с `id`, у исходящих появляется после отправки.
    var serverId: String?
    /// Дублирует `chat?.id`, чтобы фильтровать без обхода связи.
    var chatId: String
    var authorId: String
    var text: String
    /// Время отправки. Используется как курсор пагинации.
    var timestamp: Date
    var statusRaw: String
    var mediaId: String?
    /// Канонический JSON ответа, вложений, реакций и комментариев. Пустая строка — фрагмента нет.
    var contentJSON: String = ""
    /// Id поста, если это комментарий. Пустая строка — сообщение основной ленты.
    var threadOf: String = ""
    /// Имя отправителя. Пустая строка — профиль ещё не известен и уже сохранённое имя не затираем.
    var authorName: String = ""
    /// Адрес аватара отправителя. Пустая строка хранится так же, как отсутствие адреса.
    var authorAvatarURL: String = ""

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
        mediaId: String? = nil,
        serverId: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.statusRaw = status.rawValue
        self.mediaId = mediaId
    }
}
