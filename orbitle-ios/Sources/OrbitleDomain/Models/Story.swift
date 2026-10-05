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

    public init(id: String, owner: StoryOwner, time: Date, expiresAt: Date? = nil, audience: StoryAudience = .everyone, media: StoryMedia?) {
        self.id = id
        self.owner = owner
        self.time = time
        self.expiresAt = expiresAt
        self.audience = audience
        self.media = media
    }
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
