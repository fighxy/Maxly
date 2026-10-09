import Foundation
import MaxlyDomain

/// Вкладки общих медиа в профиле: фото и видео, файлы, ссылки, голосовые.
public enum SharedMediaTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case media, files, links, voice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .media: "Медиа"
        case .files: "Файлы"
        case .links: "Ссылки"
        case .voice: "Голосовые"
        }
    }
}

/// Вложения чата по вкладкам, новые первыми. Собираются из загруженной истории.
public struct SharedMedia: Equatable, Sendable {
    public struct Visual: Identifiable, Hashable, Sendable {
        public var id: String { attachmentId }
        public let message: Message
        public let attachmentId: String
        public let thumbnailURL: URL?
        public let preview: Data?
        /// `0:42` у видео, `nil` у фото.
        public let duration: String?
        /// Свой ролик на устройстве без обложки: кадр для сетки берётся из него.
        public var videoFile: URL? = nil
    }

    public struct File: Identifiable, Hashable, Sendable {
        public var id: String { file.id }
        public let message: Message
        public let file: FileContent
        /// `PDF`, `ZIP` — подпись на значке.
        public let ext: String
        /// `1,2 МБ · 12 сен`
        public let details: String
    }

    public struct Link: Identifiable, Hashable, Sendable {
        public let id: String
        public let message: Message
        public let url: URL
        /// `github.com`
        public let host: String
        /// Буква на цветном квадрате.
        public let letter: String
        /// Текст сообщения вокруг ссылки, если он не сама ссылка.
        public let context: String?
    }

    public struct Voice: Identifiable, Hashable, Sendable {
        public var id: String { voice.id }
        public let message: Message
        public let voice: VoiceContent
        public let author: String
        /// `12 сен · 0:42`
        public let details: String
    }

    public var media: [Visual] = []
    public var files: [File] = []
    public var links: [Link] = []
    public var voices: [Voice] = []

    public init() {}

    public var tabs: [SharedMediaTab] {
        SharedMediaTab.allCases.filter { count(of: $0) > 0 }
    }

    public var isEmpty: Bool { tabs.isEmpty }

    public func count(of tab: SharedMediaTab) -> Int {
        switch tab {
        case .media: media.count
        case .files: files.count
        case .links: links.count
        case .voice: voices.count
        }
    }

    /// `messages` в порядке ленты (старые сверху); вкладки — новые первыми.
    public static func collect(
        _ messages: [Message],
        currentUserId: String = "",
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> SharedMedia {
        var shared = SharedMedia()
        for message in messages.reversed() where message.status != .failed {
            let day = dayLabel(message.timestamp, calendar: calendar, now: now)
            for attachment in message.content.visuals {
                if let photo = attachment.photo {
                    shared.media.append(Visual(
                        message: message, attachmentId: photo.id,
                        thumbnailURL: photo.displayURL, preview: photo.preview, duration: nil
                    ))
                } else if let video = attachment.video, !video.isRound {
                    // Только обложка: адрес самого ролика картинкой не декодируется.
                    let local = video.localPath.map(URL.init(fileURLWithPath:))
                    shared.media.append(Visual(
                        message: message, attachmentId: video.id,
                        thumbnailURL: video.posterURL, preview: video.preview,
                        duration: ChatContentFormat.clock(ms: video.durationMs),
                        videoFile: video.posterURL == nil ? local : nil
                    ))
                }
            }
            for file in message.content.files {
                let ext = (file.name as NSString).pathExtension.uppercased()
                let size = file.size > 0 ? ChatContentFormat.fileSize(file.size) + " · " : ""
                shared.files.append(File(
                    message: message, file: file,
                    ext: ext.isEmpty || ext.count > 4 ? "FILE" : ext,
                    details: size + day
                ))
            }
            for voice in message.content.voices {
                let author = !currentUserId.isEmpty && message.authorId == currentUserId
                    ? "Вы" : (message.authorName.isEmpty ? "Голосовое сообщение" : message.authorName)
                shared.voices.append(Voice(
                    message: message, voice: voice, author: author,
                    details: day + " · " + ChatContentFormat.clock(ms: voice.durationMs)
                ))
            }
            for (index, url) in urls(in: message).enumerated() {
                let host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
                let text = message.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
                let context = text == url.absoluteString || text.isEmpty ? nil : text
                shared.links.append(Link(
                    id: "\(message.id)-\(index)",
                    message: message, url: url, host: host,
                    letter: host.first.map { String($0).uppercased() } ?? "#",
                    context: context
                ))
            }
        }
        return shared
    }

    /// Ссылки из разметки и из текста, без повторов, в порядке появления.
    static func urls(in message: Message) -> [URL] {
        var found: [URL] = []
        func add(_ url: URL?) {
            guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            if !found.contains(url) { found.append(url) }
        }
        for span in message.content.formatting ?? [] where span.kind == .link {
            add(span.url.flatMap(URL.init(string:)))
        }
        let text = message.displayText
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return found
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            var url = match.url
            // «max.ru/x» детектор отдаёт как http://; почту и телефоны пропускаем.
            if url?.scheme == nil { url = url.flatMap { URL(string: "https://" + $0.absoluteString) } }
            add(url)
        }
        return found
    }

    static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    /// `12 сен`, в прошлые годы — `12 сен 2024`.
    static func dayLabel(_ date: Date, calendar: Calendar, now: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
        let base = "\(parts.day ?? 1) \(month)"
        guard let year = parts.year, year != calendar.component(.year, from: now) else { return base }
        return "\(base) \(year)"
    }
}
