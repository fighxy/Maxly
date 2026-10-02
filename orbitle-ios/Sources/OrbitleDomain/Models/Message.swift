import Foundation

/// Статус сообщения. `sending` и `failed` бывают только у исходящих.
public enum MessageStatus: String, Codable, Hashable, Sendable {
    case sending
    case sent
    case failed
}

/// Сообщение, как его видит UI.
public struct Message: Identifiable, Hashable, Sendable {
    /// Локальный id. У исходящих это `local-<uuid>`, у входящих совпадает с серверным.
    public let id: String
    /// id на сервере. У исходящих появляется после отправки.
    public var serverId: String?
    public var chatId: String
    public var authorId: String
    public var authorName: String
    public var authorAvatarURL: URL?
    public var text: String
    public var timestamp: Date
    public var status: MessageStatus
    public var mediaId: String?
    public var content: MessageContent
    /// Своё отправленное прочитано собеседником (отметка прочтения чата не раньше его времени):
    /// в пузыре две галочки.
    public var isRead: Bool

    public init(
        id: String,
        serverId: String? = nil,
        chatId: String,
        authorId: String,
        text: String,
        timestamp: Date,
        status: MessageStatus,
        mediaId: String? = nil,
        content: MessageContent = .empty,
        authorName: String = "",
        authorAvatarURL: URL? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.chatId = chatId
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.mediaId = mediaId
        self.content = content
        self.isRead = isRead
    }

    /// Текст пузыря: свой, а у пересланного без своего текста — текст оригинала.
    public var displayText: String {
        let own = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if own.isEmpty, let forwarded = content.forward?.text, !forwarded.isEmpty { return forwarded }
        return text
    }

    /// Короткая подпись для цитаты: текст, иначе вид вложения.
    public var replySnippet: String {
        let trimmed = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !content.voices.isEmpty { return "Голосовое сообщение" }
        if content.attachments.contains(where: { $0.video != nil }) { return "Видео" }
        if content.attachments.contains(where: { $0.photo != nil }) { return "Фото" }
        if let file = content.files.first {
            let name = file.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Файл" : name
        }
        if let contact = content.attachments.compactMap(\.contact).first {
            return contact.name.isEmpty ? "Контакт" : "Контакт: \(contact.name)"
        }
        if let call = content.call {
            return call.isGroup ? "Групповой звонок" : "Звонок"
        }
        return "Сообщение"
    }

    public var replyKind: MessageReply.Kind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return .text }
        if !content.voices.isEmpty { return .voice }
        if content.attachments.contains(where: { $0.video != nil }) { return .video }
        if content.attachments.contains(where: { $0.photo != nil }) { return .photo }
        if !content.files.isEmpty { return .file }
        return .text
    }
}
