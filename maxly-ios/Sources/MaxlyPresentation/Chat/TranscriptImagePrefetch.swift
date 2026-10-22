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
        guard !messages.isEmpty else { return Plan(urls: []) }
        let span = max(1, window)
        let range: Range<Int>
        if let visible = visibleRange, !visible.isEmpty {
            let start: Int
            let end: Int
            if scrollingTowardOlder {
                start = max(0, visible.lowerBound - span)
                end = min(messages.count, visible.upperBound)
            } else {
                start = max(0, visible.lowerBound)
                end = min(messages.count, visible.upperBound + span)
            }
            range = start..<max(start + 1, end)
        } else {
            let start = max(0, messages.count - span)
            range = start..<messages.count
        }
        return Plan(urls: urls(in: messages[range]))
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
