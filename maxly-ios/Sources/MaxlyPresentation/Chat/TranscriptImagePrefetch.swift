import Foundation
import MaxlyDomain

/// Какие URL греть в `ImagePipeline` при скролле ленты.
///
/// Берём окно вокруг видимых индексов со сдвигом по направлению: вниз к новым —
/// хвост, вверх к старым — голову. Так decode попадает в кэш до появления ячейки.
public enum TranscriptImagePrefetch: Sendable {
    public static let window = 24
    public static let maxPixel = 900

    public struct Plan: Equatable, Sendable {
        public var urls: [URL]
        public init(urls: [URL]) { self.urls = urls }
    }

    /// `scrollingTowardOlder == true` — палец тянет к истории (визуальный верх).
    public static func plan(
        messages: [Message],
        visibleRange: Range<Int>?,
        scrollingTowardOlder: Bool,
        window: Int = window
    ) -> Plan {
        guard let range = range(count: messages.count, visibleRange: visibleRange, scrollingTowardOlder: scrollingTowardOlder, window: window) else {
            return Plan(urls: [])
        }
        return Plan(urls: urls(in: messages[range]))
    }

    /// Окно вокруг видимых строк со сдвигом по направлению прокрутки; `nil` — лента пуста.
    static func range(count: Int, visibleRange: Range<Int>?, scrollingTowardOlder: Bool, window: Int) -> Range<Int>? {
        guard count > 0 else { return nil }
        let span = max(1, window)
        if let visible = visibleRange, !visible.isEmpty {
            let start: Int
            let end: Int
            if scrollingTowardOlder {
                start = max(0, visible.lowerBound - span)
                end = min(count, visible.upperBound)
            } else {
                start = max(0, visible.lowerBound)
                end = min(count, visible.upperBound + span)
            }
            let from = min(start, count - 1)
            return from..<min(count, max(from + 1, end))
        }
        return max(0, count - span)..<count
    }

    /// От чего зависят адрес и размер картинки в пузыре ленты.
    public struct Frame: Sendable {
        /// Наибольшая ширина пузыря (`TranscriptBubble.Snapshot.maxWidth`).
        public var bubbleMaxWidth: Double
        /// Группа: у входящих слева аватар автора.
        public var showsAuthors: Bool
        public var allowsComments: Bool
        /// Масштаб экрана.
        public var scale: Double
        public var sizing: any ImageURLSizing

        public init(bubbleMaxWidth: Double, showsAuthors: Bool, allowsComments: Bool, scale: Double, sizing: any ImageURLSizing) {
            self.bubbleMaxWidth = bubbleMaxWidth
            self.showsAuthors = showsAuthors
            self.allowsComments = allowsComments
            self.scale = scale
            self.sizing = sizing
        }
    }

    /// Картинки строк окна ровно такими, какими их запросят пузыри: адрес с размером сервера
    /// (`fn`) по плитке и размер декодирования. Иначе в кэш легло бы не то, что читает ячейка:
    /// оригинал вместо миниатюры и под другим ключом.
    public static func requests(
        rows: [TranscriptRow],
        visibleRange: Range<Int>?,
        scrollingTowardOlder: Bool,
        window: Int = window,
        frame: Frame
    ) -> [ImagePrefetchRequest] {
        guard let range = range(count: rows.count, visibleRange: visibleRange, scrollingTowardOlder: scrollingTowardOlder, window: window) else {
            return []
        }
        return requests(in: rows[range], frame: frame)
    }

    public static func requests(in rows: ArraySlice<TranscriptRow>, frame: Frame) -> [ImagePrefetchRequest] {
        var seen = Set<ImagePrefetchRequest>()
        var result: [ImagePrefetchRequest] = []
        for row in rows.reversed() where !row.message.content.isService {
            for request in requests(for: row, frame: frame) where seen.insert(request).inserted {
                result.append(request)
            }
        }
        return result
    }

    static func requests(for row: TranscriptRow, frame: Frame) -> [ImagePrefetchRequest] {
        let message = row.message
        let content = message.content
        var result: [ImagePrefetchRequest] = []
        let layout = MessageBubbleLayout(
            message: message, showsAuthorName: frame.showsAuthors && row.showsAuthorName, showsComments: frame.allowsComments
        )
        let bubbleWidth = BubbleMetrics.bubbleWidth(
            maxWidth: max(1, frame.bubbleMaxWidth), reservesAvatar: frame.showsAuthors && !row.isOutgoing
        )
        if let album = BubbleHeightCache.mediaLayout(content, bubbleWidth: bubbleWidth, hasFill: layout.hasFill) {
            let visuals = content.visuals
            for tile in album.tiles where visuals.indices.contains(tile.index) {
                let url = tileURL(
                    visuals[tile.index], pointSize: max(tile.width, tile.height), scale: frame.scale, sizing: frame.sizing
                )
                if let url, !url.isFileURL {
                    result.append(ImagePrefetchRequest(
                        url: url, maxPixel: BubbleMetrics.tileDecodeSize(width: tile.width, height: tile.height)
                    ))
                }
            }
        }
        if frame.showsAuthors, row.showsAuthorAvatar, let avatar = message.authorAvatarURL, !avatar.isFileURL {
            let url = ImageURLRequests.url(
                avatar, shape: .square, pointSize: CGFloat(BubbleMetrics.avatarSize), scale: CGFloat(frame.scale),
                fullScreen: false, sizing: frame.sizing
            )
            if let url {
                result.append(ImagePrefetchRequest(url: url, maxPixel: BubbleMetrics.avatarDecodeSize(BubbleMetrics.avatarSize)))
            }
        }
        return result
    }

    /// Картинка плитки: своя копия фото на диске, иначе уменьшенный адрес сервера (`w_N`);
    /// у видео — обложка. Копию могли убрать (кэш, обновление приложения): тогда тоже
    /// уменьшенный адрес, а не оригинал.
    public static func tileURL(_ item: ChatAttachment, pointSize: Double, scale: Double, sizing: any ImageURLSizing) -> URL? {
        if let photo = item.photo {
            if let local = photo.localFileURL { return local }
            return ImageURLRequests.url(
                photo.url, shape: .width, pointSize: CGFloat(pointSize), scale: CGFloat(scale),
                fullScreen: false, sizing: sizing
            )
        }
        return item.video?.displayURL
    }

    public static func urls(in messages: ArraySlice<Message>) -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        for message in messages.reversed() {
            var candidates = message.content.visuals.compactMap { $0.photo?.displayURL ?? $0.video?.displayURL }
            if let avatar = message.authorAvatarURL { candidates.append(avatar) }
            for url in candidates where !url.isFileURL && seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }
}

/// Картинка, которую запросит ячейка: адрес и размер декодирования — ключ кэша картинок.
public struct ImagePrefetchRequest: Hashable, Sendable {
    public var url: URL
    public var maxPixel: Int

    public init(url: URL, maxPixel: Int) {
        self.url = url
        self.maxPixel = maxPixel
    }
}
