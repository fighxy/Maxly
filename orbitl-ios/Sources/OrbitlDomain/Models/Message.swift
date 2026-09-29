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
    public var text: String
    public var timestamp: Date
    public var status: MessageStatus
    public var mediaId: String?

    public init(
        id: String,
        serverId: String? = nil,
        chatId: String,
        authorId: String,
        text: String,
        timestamp: Date,
        status: MessageStatus,
        mediaId: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.mediaId = mediaId
    }
}
