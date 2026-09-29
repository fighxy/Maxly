import Foundation

/// Тип чата.
public enum ChatType: String, Codable, Hashable, Sendable {
    /// Личная переписка один на один.
    case `private`
    case group
    case channel

    /// Тип чата из ядра (`DIALOG`, `CHAT`, `CHANNEL`).
    public static func fromCore(_ raw: String) -> ChatType {
        switch raw.uppercased() {
        case "DIALOG", "PRIVATE": .private
        case "CHANNEL": .channel
        default: .group
        }
    }
}

/// Судьба своего последнего сообщения: от очереди до прочтения собеседником.
public enum DeliveryState: String, Codable, Hashable, Sendable {
    case sending
    case sent
    case read
    case failed
}

/// Вид вложения в последнем сообщении. По нему строка списка пишет «Фотография», «Видео»…
public enum MessageMediaKind: String, Codable, Hashable, Sendable, CaseIterable {
    case photo
    case video
    case voice
    case videoMessage
    case audio
    case file
    case sticker
    case gif
    case location
    case contact
    case poll
    case call
}

/// Последнее сообщение чата в том объёме, который нужен строке списка.
public struct ChatLastMessage: Hashable, Sendable {
    /// Автор. `nil`, если сервер его не прислал.
    public var authorId: String?
    /// Имя автора для префикса в группах. `nil`, если имя неизвестно.
    public var authorName: String?
    /// Сообщение написал текущий пользователь.
    public var isOutgoing: Bool
    /// Доставка своего сообщения. У входящих `nil`.
    public var delivery: DeliveryState?
    public var media: MessageMediaKind?
    /// Миниатюра вложения для строки (фото, видео).
    public var thumbnailURL: URL?

    public init(
        authorId: String? = nil,
        authorName: String? = nil,
        isOutgoing: Bool = false,
        delivery: DeliveryState? = nil,
        media: MessageMediaKind? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.authorId = authorId
        self.authorName = authorName
        self.isOutgoing = isOutgoing
        self.delivery = delivery
        self.media = media
        self.thumbnailURL = thumbnailURL
    }
}

/// Черновик, оставленный в поле ввода чата.
public struct ChatDraft: Hashable, Sendable {
    public var text: String
    public var updatedAt: Date

    public init(text: String, updatedAt: Date) {
        self.text = text
        self.updatedAt = updatedAt
    }
}

/// Чат, как его видит UI.
public struct Chat: Identifiable, Hashable, Sendable {
    /// id «Избранного» (сохранённые сообщения) в Max.
    public static let savedMessagesId = "0"

    public let id: String
    public var title: String
    public var type: ChatType
    public var lastMessageId: String?
    public var unreadCount: Int
    /// Время последней активности, по нему сортируется список чатов.
    public var updatedAt: Date
    /// Текст последнего сообщения для строки списка.
    public var preview: String?
    /// Автор, доставка и вложение последнего сообщения. `nil`, если о нём ничего не известно.
    public var lastMessage: ChatLastMessage?
    /// Фото чата или собеседника.
    public var avatarURL: URL?
    /// Место в закреплённых: меньше — выше. `nil`, если чат не закреплён.
    public var pinOrder: Int?
    /// Уведомления выключены: бейдж серый, у заголовка значок.
    public var isMuted: Bool
    /// Чат помечен непрочитанным вручную, хотя счётчик пуст.
    public var isMarkedUnread: Bool
    public var isArchived: Bool
    /// Собеседник — бот.
    public var isBot: Bool
    /// Официальный канал или аккаунт.
    public var isVerified: Bool
    /// Собеседник в сети (только личные чаты).
    public var isOnline: Bool
    /// Непрочитанные упоминания.
    public var unreadMentions: Int
    public var draft: ChatDraft?

    public init(
        id: String,
        title: String,
        type: ChatType,
        lastMessageId: String? = nil,
        unreadCount: Int = 0,
        updatedAt: Date,
        preview: String? = nil,
        lastMessage: ChatLastMessage? = nil,
        avatarURL: URL? = nil,
        pinOrder: Int? = nil,
        isMuted: Bool = false,
        isMarkedUnread: Bool = false,
        isArchived: Bool = false,
        isBot: Bool = false,
        isVerified: Bool = false,
        isOnline: Bool = false,
        unreadMentions: Int = 0,
        draft: ChatDraft? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.lastMessageId = lastMessageId
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
        self.preview = preview
        self.lastMessage = lastMessage
        self.avatarURL = avatarURL
        self.pinOrder = pinOrder
        self.isMuted = isMuted
        self.isMarkedUnread = isMarkedUnread
        self.isArchived = isArchived
        self.isBot = isBot
        self.isVerified = isVerified
        self.isOnline = isOnline
        self.unreadMentions = unreadMentions
        self.draft = draft
    }

    public var isPinned: Bool { pinOrder != nil }
    public var isSavedMessages: Bool { id == Self.savedMessagesId }
    /// Есть что читать: счётчик или ручная пометка.
    public var isUnread: Bool { unreadCount > 0 || isMarkedUnread }
    /// Время для сортировки: свежий черновик поднимает чат так же, как новое сообщение.
    public var activityDate: Date {
        guard let draft, draft.updatedAt > updatedAt else { return updatedAt }
        return draft.updatedAt
    }
}

extension Chat {
    /// Порядок списка: закреплённые по `pinOrder`, затем остальные по свежести, при равенстве по id.
    public static func listOrder(_ lhs: Chat, _ rhs: Chat) -> Bool {
        switch (lhs.pinOrder, rhs.pinOrder) {
        case let (l?, r?):
            return l != r ? l < r : lhs.id < rhs.id
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            let l = lhs.activityDate
            let r = rhs.activityDate
            return l != r ? l > r : lhs.id < rhs.id
        }
    }
}
