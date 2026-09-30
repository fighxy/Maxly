import Foundation

/// Ответ, вложения, реакции и счётчик комментариев одного сообщения.
public struct MessageContent: Hashable, Sendable, Codable {
    public var reply: MessageReply?
    public var attachments: [ChatAttachment]
    public var reactions: [MessageReaction]
    public var comments: CommentSummary?
    /// Сообщение живёт в треде поста и не попадает в общую ленту.
    public var threadOf: String?

    public init(
        reply: MessageReply? = nil,
        attachments: [ChatAttachment] = [],
        reactions: [MessageReaction] = [],
        comments: CommentSummary? = nil,
        threadOf: String? = nil
    ) {
        self.reply = reply
        self.attachments = attachments
        self.reactions = reactions
        self.comments = comments
        self.threadOf = threadOf
    }

    public static let empty = MessageContent()

    public var isEmpty: Bool {
        reply == nil && attachments.isEmpty && reactions.isEmpty && comments == nil && (threadOf?.isEmpty != false)
    }

    public var visuals: [ChatAttachment] {
        attachments.filter(\.isVisual)
    }

    public var voices: [VoiceContent] {
        attachments.compactMap(\.voice)
    }

    public var files: [FileContent] {
        attachments.compactMap(\.file)
    }

    public func settingLocalPath(_ path: String, attachmentId: String) -> MessageContent {
        var copy = self
        copy.attachments = attachments.map { $0.withLocalPath(path, id: attachmentId) }
        return copy
    }
}

/// Цитата сообщения, на которое ответили.
public struct MessageReply: Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case text
        case voice
        case photo
        case video
        case file
    }

    public var messageId: String
    public var authorName: String
    public var preview: String
    public var kind: Kind

    public init(messageId: String, authorName: String, preview: String, kind: Kind) {
        self.messageId = messageId
        self.authorName = authorName
        self.preview = preview
        self.kind = kind
    }
}

/// Вложение, которое рисуется в пузыре.
public enum ChatAttachment: Hashable, Sendable, Codable {
    case photo(PhotoContent)
    case video(VideoContent)
    case voice(VoiceContent)
    case file(FileContent)

    public var id: String {
        switch self {
        case .photo(let item): item.id
        case .video(let item): item.id
        case .voice(let item): item.id
        case .file(let item): item.id
        }
    }

    public var isVisual: Bool {
        photo != nil || video != nil
    }

    public var photo: PhotoContent? {
        if case .photo(let item) = self { return item }
        return nil
    }

    public var video: VideoContent? {
        if case .video(let item) = self { return item }
        return nil
    }

    public var voice: VoiceContent? {
        if case .voice(let item) = self { return item }
        return nil
    }

    public var file: FileContent? {
        if case .file(let item) = self { return item }
        return nil
    }

    public func withLocalPath(_ path: String, id: String) -> ChatAttachment {
        switch self {
        case .photo(var item):
            guard item.id == id else { return self }
            item.localPath = path
            return .photo(item)
        case .video(var item):
            guard item.id == id else { return self }
            item.localPath = path
            return .video(item)
        case .voice(var item):
            guard item.id == id else { return self }
            item.localPath = path
            return .voice(item)
        case .file(var item):
            guard item.id == id else { return self }
            item.localPath = path
            return .file(item)
        }
    }
}

public struct PhotoContent: Hashable, Sendable, Codable {
    public var id: String
    public var url: URL?
    public var width: Int?
    public var height: Int?
    public var localPath: String?

    public init(id: String, url: URL?, width: Int? = nil, height: Int? = nil, localPath: String? = nil) {
        self.id = id
        self.url = url
        self.width = width
        self.height = height
        self.localPath = localPath
    }

    public var displayURL: URL? {
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        return url
    }

    public func cacheItem() -> MediaItem? {
        guard let url else { return nil }
        return MediaItem(id: id, type: .image, url: url, size: 0, localPath: localPath)
    }
}

public struct VideoContent: Hashable, Sendable, Codable {
    public var id: String
    public var url: URL?
    public var posterURL: URL?
    public var width: Int?
    public var height: Int?
    public var durationMs: Int64
    /// Круглое видеосообщение.
    public var isRound: Bool
    public var localPath: String?

    public init(
        id: String,
        url: URL?,
        posterURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int64 = 0,
        isRound: Bool = false,
        localPath: String? = nil
    ) {
        self.id = id
        self.url = url
        self.posterURL = posterURL
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.isRound = isRound
        self.localPath = localPath
    }

    /// Постер остаётся картинкой пузыря. Скачанный ролик — это файл видео, его не подставляем вместо кадра.
    public var displayURL: URL? {
        if let posterURL { return posterURL }
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        return url
    }

    public var playbackURL: URL? {
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        return url
    }

    public func cacheItem() -> MediaItem? {
        guard let url else { return nil }
        return MediaItem(id: id, type: .video, url: url, size: 0, localPath: localPath)
    }
}

public struct VoiceContent: Hashable, Sendable, Codable {
    public var id: String
    public var url: URL?
    /// Амплитуды 0…255. Пустой список — ровная дорожка.
    public var waveform: [Int]
    public var durationMs: Int64
    public var transcript: String?
    public var localPath: String?

    public init(
        id: String,
        url: URL?,
        waveform: [Int] = [],
        durationMs: Int64 = 0,
        transcript: String? = nil,
        localPath: String? = nil
    ) {
        self.id = id
        self.url = url
        self.waveform = waveform
        self.durationMs = durationMs
        self.transcript = transcript
        self.localPath = localPath
    }

    /// Файл только если он уже лежит на диске. Адрес сервера сам по себе не играет.
    public var fileURL: URL? {
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        return nil
    }

    public func cacheItem() -> MediaItem? {
        guard let url else { return nil }
        return MediaItem(id: id, type: .audio, url: url, size: 0, localPath: localPath)
    }
}

/// Файл. Адрес только если сервер его прислал: токен сам по себе файлом не открывается.
public struct FileContent: Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var size: Int64
    public var url: URL?
    public var localPath: String?

    public init(id: String, name: String, size: Int64 = 0, url: URL? = nil, localPath: String? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.url = url
        self.localPath = localPath
    }

    public var fileURL: URL? {
        if let localPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        return nil
    }

    public func cacheItem() -> MediaItem? {
        guard let url else { return nil }
        return MediaItem(id: id, type: .file, url: url, size: size, localPath: localPath)
    }
}

public struct MessageReaction: Hashable, Sendable, Codable {
    public var emoji: String
    public var count: Int
    public var mine: Bool

    public init(emoji: String, count: Int, mine: Bool) {
        self.emoji = emoji
        self.count = count
        self.mine = mine
    }
}

public struct CommentSummary: Hashable, Sendable, Codable {
    public var count: Int

    public init(count: Int) {
        self.count = count
    }
}

extension Array where Element == MessageReaction {
    /// Ставит реакцию или снимает свою. Чужие счётчики не обнуляются.
    public func toggled(_ emoji: String) -> [MessageReaction] {
        var next = self
        if let index = next.firstIndex(where: { $0.emoji == emoji && $0.mine }) {
            next[index].count -= 1
            next[index].mine = false
            return next.filter { $0.count > 0 }
        }
        for index in next.indices where next[index].mine {
            next[index].count = Swift.max(0, next[index].count - 1)
            next[index].mine = false
        }
        next.removeAll { $0.count <= 0 }
        if let index = next.firstIndex(where: { $0.emoji == emoji }) {
            next[index].count += 1
            next[index].mine = true
        } else {
            next.append(MessageReaction(emoji: emoji, count: 1, mine: true))
        }
        return next
    }
}
