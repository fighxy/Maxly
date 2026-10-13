import Foundation

/// Чья история: человек, группа или канал. Лента собирает истории по владельцам.
public struct StoryOwner: Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable {
        case user = 0
        case chat = 1
        case channel = 2
    }

    public var id: String
    public var kind: Kind

    public init(id: String, kind: Kind = .user) {
        self.id = id
        self.kind = kind
    }
}

/// Кольцо владельца в ленте: сколько у него историй и сколько из них уже просмотрено.
/// `name` и `avatarURL` — из профиля владельца, пустые, если он неизвестен.
public struct StoryRing: Hashable, Sendable {
    public var owner: StoryOwner
    public var name: String
    public var avatarURL: URL?
    public var updatedAt: Date
    public var total: Int
    public var read: Int
    public var expiresAt: Date?

    public init(owner: StoryOwner, name: String, avatarURL: URL? = nil, updatedAt: Date, total: Int, read: Int, expiresAt: Date? = nil) {
        self.owner = owner
        self.name = name
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
        self.total = total
        self.read = read
        self.expiresAt = expiresAt
    }

    public var unread: Int { max(0, total - read) }
    public var hasUnread: Bool { unread > 0 }
    /// Историй не осталось: кольцо убирается.
    public var isEmpty: Bool { total <= 0 }
}

/// Кто видит опубликованную историю.
public enum StoryAudience: Int, Hashable, Sendable {
    case everyone = 1
    case contacts = 2
}

/// Фото или видео истории: `url` — картинка или MP4, у видео `thumbnailURL` — обложка.
public struct StoryMedia: Hashable, Sendable {
    public var isVideo: Bool
    public var url: URL
    public var thumbnailURL: URL?
    public var width: Int?
    public var height: Int?
    /// Длина видео в секундах.
    public var duration: TimeInterval?

    public init(isVideo: Bool, url: URL, thumbnailURL: URL? = nil, width: Int? = nil, height: Int? = nil, duration: TimeInterval? = nil) {
        self.isVideo = isVideo
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.duration = duration
    }
}

/// Одна история. `media` `nil`, если сервер прислал то, что клиент не умеет показать.
public struct Story: Identifiable, Hashable, Sendable {
    public var id: String
    public var owner: StoryOwner
    public var time: Date
    public var expiresAt: Date?
    public var audience: StoryAudience
    public var media: StoryMedia?
    /// Свой лайк (эмодзи), `nil` — лайка нет.
    public var reaction: String?
    /// Биты автора (`StoryFlags`): кому видна и что он выключил у этой истории.
    public var settings: Int
    public var viewsCount: Int

    public init(id: String, owner: StoryOwner, time: Date, expiresAt: Date? = nil, audience: StoryAudience = .everyone, media: StoryMedia?,
                reaction: String? = nil, settings: Int = 0, viewsCount: Int = 0) {
        self.id = id
        self.owner = owner
        self.time = time
        self.expiresAt = expiresAt
        self.audience = audience
        self.media = media
        self.reaction = reaction
        self.settings = settings
        self.viewsCount = viewsCount
    }

    public var isLiked: Bool { reaction != nil }
    public var canLike: Bool { settings & StoryFlags.offReact == 0 }
    public var canReply: Bool { settings & StoryFlags.offReply == 0 }
    public var canOpenProfile: Bool { settings & StoryFlags.offMenuProfile == 0 }
    public var canHideAuthor: Bool { settings & StoryFlags.offMenuHideAuthor == 0 }
    public var canDownload: Bool { settings & StoryFlags.offMenuDownload == 0 }
    public var canReport: Bool { settings & StoryFlags.offMenuReport == 0 }
}

/// Биты `settings` истории (как у веб-клиента Max): что автор выключил у этой истории.
public enum StoryFlags {
    public static let visibleForContacts = 2
    public static let offReact = 4
    public static let offReply = 8
    public static let offMenuProfile = 16
    public static let offMenuHideAuthor = 32
    public static let offMenuDownload = 64
    public static let offMenuReport = 128
    /// Лайк кнопки-сердечка.
    public static let heart = "❤️"
}

/// Истории владельца: свежее кольцо (`nil` — историй больше нет) и сами истории, от старых к новым.
public struct OwnerStories: Hashable, Sendable {
    public var ring: StoryRing?
    public var stories: [Story]

    public init(ring: StoryRing?, stories: [Story]) {
        self.ring = ring
        self.stories = stories
    }
}

/// Страница архива своих историй (`STORIES_HISTORY_GET_BY_OWNER_ID` 219). `marker` — курсор
/// следующей страницы; пусто — страниц больше нет.
public struct StoryArchivePage: Hashable, Sendable {
    public var stories: [Story]
    public var marker: String

    public init(stories: [Story], marker: String) {
        self.stories = stories
        self.marker = marker
    }

    /// Последняя страница: сервер не прислал курсор (или прислал `0`).
    public var isLast: Bool { marker.isEmpty || marker == "0" }
}

/// Файл новой истории на устройстве: фото или видео, у видео — длина, если известна.
public struct OutgoingStory: Hashable, Sendable {
    public var fileURL: URL
    public var isVideo: Bool
    public var duration: TimeInterval?

    public init(fileURL: URL, isVideo: Bool, duration: TimeInterval? = nil) {
        self.fileURL = fileURL
        self.isVideo = isVideo
        self.duration = duration
    }
}
