import Foundation

/// Стикер в сообщении (`attaches[]` `_type: STICKER`). С `lottieURL` он анимированный.
public struct StickerContent: Hashable, Sendable, Codable {
    /// id вложения в сообщении; у стикеров это id стикера.
    public var id: String
    public var stickerId: String
    public var url: URL?
    public var lottieURL: URL?
    public var width: Int?
    public var height: Int?

    public init(id: String, stickerId: String, url: URL?, lottieURL: URL? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.stickerId = stickerId
        self.url = url
        self.lottieURL = lottieURL
        self.width = width
        self.height = height
    }

    public var isAnimated: Bool { lottieURL != nil }
}

/// Стикер каталога сервера.
public struct Sticker: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var url: URL?
    public var lottieURL: URL?
    public var setId: String?
    public var width: Int?
    public var height: Int?
    /// Эмодзи, к которым подходит стикер.
    public var tags: [String]

    public init(id: String, url: URL?, lottieURL: URL? = nil, setId: String? = nil, width: Int? = nil, height: Int? = nil, tags: [String] = []) {
        self.id = id
        self.url = url
        self.lottieURL = lottieURL
        self.setId = setId
        self.width = width
        self.height = height
        self.tags = tags
    }

    public var isAnimated: Bool { lottieURL != nil }

    /// Вложение сообщения с этим стикером — пузырь до ответа сервера.
    public var content: StickerContent {
        StickerContent(id: id, stickerId: id, url: url, lottieURL: lottieURL, width: width, height: height)
    }
}

/// Набор стикеров: обложка и id стикеров по порядку.
public struct StickerSet: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var name: String
    public var iconURL: URL?
    public var stickerIds: [String]
    public var link: String?
    /// Набор добавлен в свои.
    public var isFavorite: Bool

    public init(id: String, name: String, iconURL: URL? = nil, stickerIds: [String], link: String? = nil, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.stickerIds = stickerIds
        self.link = link
        self.isFavorite = isFavorite
    }
}

/// Наборы панели (свои первыми) и недавние стикеры сервера.
public struct StickerCatalog: Hashable, Sendable, Codable {
    public var sets: [StickerSet]
    public var recentStickerIds: [String]

    public init(sets: [StickerSet] = [], recentStickerIds: [String] = []) {
        self.sets = sets
        self.recentStickerIds = recentStickerIds
    }
}

/// Анимированный эмодзи сервера (анимодзи): эмодзи со своей Lottie-анимацией.
public struct AnimatedEmoji: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var emoji: String
    public var iconURL: URL?
    public var lottieURL: URL?

    public init(id: String, emoji: String, iconURL: URL? = nil, lottieURL: URL? = nil) {
        self.id = id
        self.emoji = emoji
        self.iconURL = iconURL
        self.lottieURL = lottieURL
    }
}

/// Стикеры и анимодзи сервера. Каталоги кэшируются: панель открывается сразу.
public protocol StickerRepository: Sendable {
    /// Каталог из кэша, если он есть.
    func cachedCatalog() async -> StickerCatalog?
    func catalog() async throws(MaxlyError) -> StickerCatalog
    /// Стикеры по id в том же порядке; неизвестные пропущены. Известные берутся из кэша.
    func stickers(ids: [String]) async throws(MaxlyError) -> [Sticker]
    func cachedAnimatedEmoji() async -> [AnimatedEmoji]
    func animatedEmoji() async throws(MaxlyError) -> [AnimatedEmoji]
}

/// Недавние эмодзи и стикеры этого устройства, новые первыми.
public protocol RecentStickerStore: Sendable {
    func recentEmoji() async -> [String]
    func noteEmoji(_ emoji: String) async
    func recentStickers() async -> [Sticker]
    func noteSticker(_ sticker: Sticker) async
}
