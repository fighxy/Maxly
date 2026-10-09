import Foundation
import MaxlyDomain

// Sendable-записи, в которых данные ходят между сервером, очередью и базой.
// Поля совпадают с доменными моделями `Chat` и `Message`. Отдельные типы нужны,
// чтобы формат серверного ответа можно было менять, не трогая домен.

public struct ChatRecord: Sendable, Hashable {
    public var id: String
    public var title: String
    public var type: ChatType
    public var lastMessageId: String?
    public var unreadCount: Int
    public var updatedAt: Date
    public var preview: String?
    // Поля ниже сервер присылает не всегда. `nil` значит «неизвестно», и слияние
    // оставляет то, что уже лежит в базе.
    /// Автор последнего сообщения.
    public var lastAuthorId: String?
    public var avatarURL: URL?
    public var isMuted: Bool?
    public var isArchived: Bool?
    public var isBot: Bool?
    public var isVerified: Bool?
    /// Порядок закреплённых с сервера. Учитывается, только если `pinsKnown`.
    public var pinOrder: Int?
    /// Сервер прислал закреплённые: тогда `pinOrder == nil` значит «не закреплён».
    public var pinsKnown: Bool
    /// Вид первого вложения последнего сообщения. `nil` — текст или неизвестно.
    public var lastMedia: MessageMediaKind?
    public var lastThumbnailURL: URL?
    /// Комментарии канала. `nil` — сервер не сказал.
    public var commentsEnabled: Bool?
    /// Можно ли писать. `nil` — сервер не сказал.
    public var canWrite: Bool?
    /// Имя автора последнего сообщения (для «Имя:» в группах). `nil` — неизвестно.
    public var lastAuthorName: String?
    /// Последнее сообщение своё. `nil` — неизвестно.
    public var lastOutgoing: Bool?
    /// Последнее сообщение — пересылка: превью и вложение взяты из пересланного.
    public var lastForwarded: Bool
    /// Запись полная (строка списка сервера): пустой `lastMessageId` значит «сообщений
    /// нет», а не «неизвестно», и прежнее превью очищается.
    public var lastKnown: Bool
    /// Отметка прочтения других участников, мс (`participants` карточки чата). `0` — не сказано.
    public var peerReadMark: Int64
    /// Серверное время последнего сообщения, мс (с ним сравниваются отметки прочтения).
    /// `0` — неизвестно: пуши чата его не несут.
    public var lastMessageAt: Int64
    /// Аккаунт участвует в чате. Не хранится: неактивный чат из ответа сервера убирается из
    /// списка (как в Komet), а не записывается.
    public var isActive: Bool = true
    /// Диалог с ботом, у которого есть мини-приложение: в списке чатов кнопка «Открыть».
    /// `nil` — неизвестно, в базе остаётся прежнее значение.
    public var hasWebApp: Bool?

    public init(
        id: String,
        title: String,
        type: ChatType,
        lastMessageId: String? = nil,
        unreadCount: Int = 0,
        updatedAt: Date,
        preview: String? = nil,
        lastAuthorId: String? = nil,
        avatarURL: URL? = nil,
        isMuted: Bool? = nil,
        isArchived: Bool? = nil,
        isBot: Bool? = nil,
        isVerified: Bool? = nil,
        pinOrder: Int? = nil,
        pinsKnown: Bool = false,
        lastMedia: MessageMediaKind? = nil,
        lastThumbnailURL: URL? = nil,
        commentsEnabled: Bool? = nil,
        canWrite: Bool? = nil,
        lastAuthorName: String? = nil,
        lastOutgoing: Bool? = nil,
        lastForwarded: Bool = false,
        lastKnown: Bool = false,
        peerReadMark: Int64 = 0,
        lastMessageAt: Int64 = 0
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
        self.preview = preview
        self.lastAuthorId = lastAuthorId
        self.avatarURL = avatarURL
        self.isMuted = isMuted
        self.isArchived = isArchived
        self.isBot = isBot
        self.isVerified = isVerified
        self.pinOrder = pinOrder
        self.pinsKnown = pinsKnown
        self.lastMedia = lastMedia
        self.lastThumbnailURL = lastThumbnailURL
        self.commentsEnabled = commentsEnabled
        self.canWrite = canWrite
        self.lastAuthorName = lastAuthorName
        self.lastOutgoing = lastOutgoing
        self.lastForwarded = lastForwarded
        self.lastKnown = lastKnown
        self.peerReadMark = peerReadMark
        self.lastMessageAt = lastMessageAt
    }

    public init(_ chat: Chat) {
        self.init(
            id: chat.id,
            title: chat.title,
            type: chat.type,
            lastMessageId: chat.lastMessageId,
            unreadCount: chat.unreadCount,
            updatedAt: chat.updatedAt,
            preview: chat.preview,
            lastAuthorId: chat.lastMessage?.authorId,
            avatarURL: chat.avatarURL,
            isMuted: chat.isMuted,
            isArchived: chat.isArchived,
            isBot: chat.isBot,
            isVerified: chat.isVerified,
            lastMedia: chat.lastMessage?.media,
            lastThumbnailURL: chat.lastMessage?.thumbnailURL,
            commentsEnabled: chat.commentsEnabled,
            canWrite: chat.canWrite
        )
        // Из домена — только «да»: снимает флаг лишь ответ ядра.
        self.hasWebApp = chat.hasWebApp ? true : nil
    }

    public var domain: Chat {
        Chat(
            id: id,
            title: title,
            type: type,
            lastMessageId: lastMessageId,
            unreadCount: unreadCount,
            updatedAt: updatedAt,
            preview: preview,
            lastMessage: (lastAuthorId != nil || lastMedia != nil)
                ? ChatLastMessage(authorId: lastAuthorId, media: lastMedia, thumbnailURL: lastThumbnailURL)
                : nil,
            avatarURL: avatarURL,
            pinOrder: pinsKnown ? pinOrder : nil,
            isMuted: isMuted ?? false,
            isArchived: isArchived ?? false,
            isBot: isBot ?? false,
            isVerified: isVerified ?? false,
            commentsEnabled: commentsEnabled,
            canWrite: canWrite,
            hasWebApp: hasWebApp ?? false
        )
    }
}

public struct MessageRecord: Sendable, Hashable {
    public var id: String
    public var serverId: String?
    public var chatId: String
    public var authorId: String
    public var text: String
    public var timestamp: Date
    public var status: MessageStatus
    public var mediaId: String?
    public var contentJSON: String
    public var threadOf: String
    public var authorName: String
    public var authorAvatarURL: String
    /// Реакции в `contentJSON` пришли от сервера и точны. Иначе при записи в базу остаются
    /// прежние: ответ на правку и другие частичные записи реакций не несут. В базе не хранится.
    public var reactionsKnown: Bool
    /// Время последней правки (`updateTime`, мс). `0` — не правили или источник не сказал:
    /// уже сохранённое время такой записью не затирается.
    public var updateTimeMs: Int64

    public init(
        id: String,
        serverId: String? = nil,
        chatId: String,
        authorId: String,
        text: String,
        timestamp: Date,
        status: MessageStatus,
        mediaId: String? = nil,
        contentJSON: String = "",
        threadOf: String = "",
        authorName: String = "",
        authorAvatarURL: String = "",
        reactionsKnown: Bool = false,
        updateTimeMs: Int64 = 0
    ) {
        self.id = id
        self.serverId = serverId
        self.chatId = chatId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.status = status
        self.mediaId = mediaId
        self.contentJSON = contentJSON
        self.threadOf = threadOf
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.reactionsKnown = reactionsKnown
        self.updateTimeMs = updateTimeMs
    }

    public init(_ message: Message) {
        self.init(
            id: message.id,
            serverId: message.serverId,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: message.timestamp,
            status: message.status,
            mediaId: message.mediaId,
            contentJSON: MessageContentCodec.encode(message.content),
            threadOf: message.content.threadOf ?? "",
            authorName: message.authorName,
            authorAvatarURL: message.authorAvatarURL?.absoluteString ?? "",
            updateTimeMs: message.editedAt?.unixMillis ?? 0
        )
    }

    public var domain: Message {
        var content = MessageContentCodec.decode(contentJSON)
        if !threadOf.isEmpty { content.threadOf = threadOf }
        return Message(
            id: id,
            serverId: serverId,
            chatId: chatId,
            authorId: authorId,
            text: text,
            timestamp: timestamp,
            status: status,
            mediaId: mediaId,
            content: content,
            authorName: authorName,
            authorAvatarURL: authorAvatarURL.isEmpty ? nil : URL(string: authorAvatarURL),
            editedAt: updateTimeMs > 0 ? Date(unixMillis: updateTimeMs) : nil
        )
    }
}
