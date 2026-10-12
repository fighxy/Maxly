import Foundation

/// Новое чужое сообщение, только что пришедшее пушем ядра. По нему приложение, пока оно
/// в фоне, показывает уведомление (`docs/background.md`). Без текста — `media`.
public struct IncomingMessageNotice: Sendable, Equatable {
    public let chatId: String
    public let messageId: String
    public let chatTitle: String
    public let chatType: ChatType
    public let authorName: String
    public let text: String
    public let media: MessageMediaKind?
    public let isMuted: Bool

    public init(
        chatId: String,
        messageId: String,
        chatTitle: String,
        chatType: ChatType,
        authorName: String,
        text: String,
        media: MessageMediaKind?,
        isMuted: Bool
    ) {
        self.chatId = chatId
        self.messageId = messageId
        self.chatTitle = chatTitle
        self.chatType = chatType
        self.authorName = authorName
        self.text = text
        self.media = media
        self.isMuted = isMuted
    }
}

/// Кто узнаёт о новых чужих сообщениях. Вызывается один раз на сообщение, после записи в базу.
public protocol IncomingMessageSink: Sendable {
    func incoming(_ notice: IncomingMessageNotice) async
}
