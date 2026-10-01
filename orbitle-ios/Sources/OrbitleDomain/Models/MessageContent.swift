import Foundation

/// Ответ, вложения, реакции и счётчик комментариев одного сообщения.
public struct MessageContent: Hashable, Sendable, Codable {
    public var reply: MessageReply?
    public var attachments: [ChatAttachment]
    public var reactions: [MessageReaction]
    public var comments: CommentSummary?
    /// Сообщение живёт в треде поста и не попадает в общую ленту.
    public var threadOf: String?
    /// Форматирование текста. Необязательное поле: старые записи в базе его не содержат.
    public var formatting: [TextSpan]?
    /// Сообщение переслано: чьё и с каким текстом. Необязательное поле, как и `formatting`.
    public var forward: MessageForward?
    /// Текст сообщения меняли после отправки.
    public var edited: Bool?
    /// Своё сообщение с вложениями, которые ещё не загружены: что и откуда отправлять.
    /// Есть, пока сообщение не принято сервером; по нему работает повтор после сбоя.
    public var drafts: [AttachmentDraft]?

    public init(
        reply: MessageReply? = nil,
        attachments: [ChatAttachment] = [],
        reactions: [MessageReaction] = [],
        comments: CommentSummary? = nil,
        threadOf: String? = nil,
        formatting: [TextSpan]? = nil,
        forward: MessageForward? = nil,
        edited: Bool? = nil,
        drafts: [AttachmentDraft]? = nil
    ) {
        self.reply = reply
        self.attachments = attachments
        self.reactions = reactions
        self.comments = comments
        self.threadOf = threadOf
        self.formatting = formatting?.isEmpty == true ? nil : formatting
        self.forward = forward
        self.edited = edited == true ? true : nil
        self.drafts = drafts?.isEmpty == true ? nil : drafts
    }

    public static let empty = MessageContent()

    public var isEmpty: Bool {
        reply == nil && attachments.isEmpty && reactions.isEmpty && comments == nil && (threadOf?.isEmpty != false)
            && (formatting?.isEmpty != false) && forward == nil && edited != true && (drafts?.isEmpty != false)
    }

    /// Вложения ещё загружаются или ждут повтора.
    public var hasPendingUploads: Bool {
        drafts?.isEmpty == false
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

    public var contacts: [ContactContent] {
        attachments.compactMap(\.contact)
    }

    /// Вид первого вложения для строки списка чатов.
    public var previewMedia: MessageMediaKind? {
        switch attachments.first {
        case .photo: .photo
        case .video(let video): video.isRound ? .videoMessage : .video
        case .voice: .voice
        case .file: .file
        case .contact: .contact
        case nil: nil
        }
    }

    /// Картинка первого вложения для строки списка: фото или обложка видео.
    public var previewThumbnail: URL? {
        switch attachments.first {
        case .photo(let photo): photo.url
        case .video(let video): video.posterURL
        default: nil
        }
    }

    public func settingLocalPath(_ path: String, attachmentId: String) -> MessageContent {
        var copy = self
        copy.attachments = attachments.map { $0.withLocalPath(path, id: attachmentId) }
        return copy
    }
}

/// Отрезок форматирования текста. `from` и `length` — в единицах UTF-16, как их шлёт сервер.
public struct TextSpan: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case strong
        case emphasized
        case underline
        case strikethrough
        case monospaced
        case heading
        case quote
        case link
        case mention
    }

    public var kind: Kind
    public var from: Int
    public var length: Int
    /// Адрес ссылки (`LINK`).
    public var url: String?
    /// Пользователь упоминания (`USER_MENTION`).
    public var userId: String?

    public init(kind: Kind, from: Int, length: Int, url: String? = nil, userId: String? = nil) {
        self.kind = kind
        self.from = from
        self.length = length
        self.url = url
        self.userId = userId
    }
}

/// Пересланное сообщение: автор оригинала и его текст (у пересылки свой текст пустой).
public struct MessageForward: Hashable, Sendable, Codable {
    public var authorName: String
    public var text: String

    public init(authorName: String, text: String) {
        self.authorName = authorName
        self.text = text
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
    case contact(ContactContent)

    public var id: String {
        switch self {
        case .photo(let item): item.id
        case .video(let item): item.id
        case .voice(let item): item.id
        case .file(let item): item.id
        case .contact(let item): item.id
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

    public var contact: ContactContent? {
        if case .contact(let item) = self { return item }
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
        case .contact:
            return self
        }
    }
}

public struct PhotoContent: Hashable, Sendable, Codable {
    public var id: String
    public var url: URL?
    public var width: Int?
    public var height: Int?
    public var localPath: String?
    /// Крошечная миниатюра (WebP) из самого вложения: её видно, пока грузится фото.
    public var preview: Data?

    public init(id: String, url: URL?, width: Int? = nil, height: Int? = nil, localPath: String? = nil, preview: Data? = nil) {
        self.id = id
        self.url = url
        self.width = width
        self.height = height
        self.localPath = localPath
        self.preview = preview
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
    /// Крошечная миниатюра (WebP) из самого вложения.
    public var preview: Data?

    public init(
        id: String,
        url: URL?,
        posterURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int64 = 0,
        isRound: Bool = false,
        localPath: String? = nil,
        preview: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.posterURL = posterURL
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.isRound = isRound
        self.localPath = localPath
        self.preview = preview
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
        return MediaItem(id: id, type: isRound ? .videoNote : .video, url: url, size: 0, localPath: localPath)
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

/// Карточка пользователя MAX, отправленная как вложение.
public struct ContactContent: Hashable, Sendable, Codable {
    /// id вложения в пузыре.
    public var id: String
    /// id пользователя MAX. Пусто, если сервер его не прислал.
    public var userId: String
    public var name: String
    /// Номер как его прислал сервер, пусто — скрыт.
    public var phone: String
    public var avatarURL: URL?

    public init(id: String, userId: String, name: String, phone: String = "", avatarURL: URL? = nil) {
        self.id = id
        self.userId = userId
        self.name = name
        self.phone = phone
        self.avatarURL = avatarURL
    }
}

/// Вложение своего сообщения до загрузки: локальный файл или карточка контакта.
/// Лежит в `MessageContent.drafts`, пока сервер не принял сообщение.
public struct AttachmentDraft: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Фото, сервер его пережимает.
        case photo
        case video
        /// Документ как есть, без сжатия.
        case file
        /// Карточка пользователя MAX, файла нет.
        case contact
        /// Записанное голосовое: Ogg/Opus, длительность и дорожка громкости.
        case voice
        /// Записанное круглое видеосообщение: квадратный MP4.
        case videoNote
    }

    public var kind: Kind
    /// Путь к локальной копии файла. Пусто у контакта.
    public var path: String
    /// Имя, которое увидит получатель файла. У фото — ASCII-имя вида `image.jpg`.
    public var fileName: String
    public var size: Int64
    public var width: Int?
    public var height: Int?
    public var durationMs: Int64
    /// Контакт: id пользователя MAX, имя и номер для пузыря.
    public var contactId: String
    public var contactName: String
    public var contactPhone: String
    /// Голосовое: уровни громкости 0…255 для дорожки (80 столбиков).
    public var waveform: [Int]

    public init(
        kind: Kind,
        path: String = "",
        fileName: String = "",
        size: Int64 = 0,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int64 = 0,
        contactId: String = "",
        contactName: String = "",
        contactPhone: String = "",
        waveform: [Int] = []
    ) {
        self.kind = kind
        self.path = path
        self.fileName = fileName
        self.size = size
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.contactId = contactId
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.waveform = waveform
    }

    private enum CodingKeys: String, CodingKey {
        case kind, path, fileName, size, width, height, durationMs, contactId, contactName, contactPhone, waveform
    }

    /// Черновики лежат в базе: старые записи без `waveform` читаются с пустой дорожкой.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        durationMs = try c.decodeIfPresent(Int64.self, forKey: .durationMs) ?? 0
        contactId = try c.decodeIfPresent(String.self, forKey: .contactId) ?? ""
        contactName = try c.decodeIfPresent(String.self, forKey: .contactName) ?? ""
        contactPhone = try c.decodeIfPresent(String.self, forKey: .contactPhone) ?? ""
        waveform = try c.decodeIfPresent([Int].self, forKey: .waveform) ?? []
    }

    public static func voice(path: String, durationMs: Int64, waveform: [Int]) -> AttachmentDraft {
        AttachmentDraft(kind: .voice, path: path, fileName: "voice.ogg", durationMs: durationMs, waveform: waveform)
    }

    public static func videoNote(path: String, durationMs: Int64, side: Int) -> AttachmentDraft {
        AttachmentDraft(kind: .videoNote, path: path, fileName: "note.mp4", width: side, height: side, durationMs: durationMs)
    }

    /// Записи голосом и кружком уходят одни, без подписи.
    public var isRecording: Bool { kind == .voice || kind == .videoNote }

    public static func contact(id: String, name: String, phone: String = "") -> AttachmentDraft {
        AttachmentDraft(kind: .contact, contactId: id, contactName: name, contactPhone: phone)
    }

    /// Как вложение выглядит в пузыре до ответа сервера. `index` делает id уникальным в сообщении.
    public func preview(index: Int) -> ChatAttachment {
        let id = "draft-\(index)"
        let local = path.isEmpty ? nil : path
        switch kind {
        case .photo:
            return .photo(PhotoContent(id: id, url: nil, width: width, height: height, localPath: local))
        case .video:
            return .video(VideoContent(id: id, url: nil, width: width, height: height, durationMs: durationMs, localPath: local))
        case .file:
            let name = fileName.isEmpty ? (path as NSString).lastPathComponent : fileName
            return .file(FileContent(id: id, name: name.isEmpty ? "Файл" : name, size: size, localPath: local))
        case .contact:
            return .contact(ContactContent(id: id, userId: contactId, name: contactName, phone: contactPhone))
        case .voice:
            return .voice(VoiceContent(id: id, url: nil, waveform: waveform, durationMs: durationMs, localPath: local))
        case .videoNote:
            // Кадр для кружка до ответа сервера: `poster.jpg` рядом с роликом, если записан.
            let poster = local.map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("poster.jpg") }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            return .video(VideoContent(
                id: id, url: nil, posterURL: poster, width: width, height: height,
                durationMs: durationMs, isRound: true, localPath: local
            ))
        }
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
