import Foundation
import MaxlyDomain

/// Где в тексте сообщения играют анимодзи (Lottie). Отметка `ANIMOJI` сервера несёт ссылку на
/// Lottie; если ссылки нет, она берётся из каталога анимодзи (`catalog`: эмодзи → ссылка).
/// Крупные эмодзи (сообщение из одних эмодзи) играют все, у кого есть анимация: по отметке,
/// иначе по каталогу — как в Max. Тот же разбор, что у Android и ПК.
public enum AnimojiText {
    /// Анимодзи в тексте: `from` и `length` в UTF-16, как у отметок.
    public struct Placed: Hashable, Sendable {
        public let from: Int
        public let length: Int
        public let emoji: String
        public let lottieURL: URL

        public init(from: Int, length: Int, emoji: String, lottieURL: URL) {
            self.from = from
            self.length = length
            self.emoji = emoji
            self.lottieURL = lottieURL
        }
    }

    /// Анимодзи внутри обычного текста: только отмеченные, без отметки эмодзи остаются буквами.
    public static func inline(text: String, spans: [TextSpan], catalog: [String: URL]) -> [Placed] {
        let units = text as NSString
        return spans
            .filter { $0.kind == .animoji }
            .compactMap { span -> Placed? in
                let start = min(max(span.from, 0), units.length)
                let end = min(max(span.from + span.length, start), units.length)
                guard end > start else { return nil }
                let emoji = units.substring(with: NSRange(location: start, length: end - start))
                let marked = span.url.flatMap { $0.isEmpty ? nil : URL(string: $0) }
                guard let url = marked ?? lookup(catalog: catalog, emoji: emoji) else { return nil }
                return Placed(from: start, length: end - start, emoji: emoji, lottieURL: url)
            }
            .sorted { $0.from < $1.from }
    }

    /// Анимация для каждого из `emoji` — крупных эмодзи сообщения `text` по порядку; `nil` —
    /// эмодзи без анимации, рисуется буквой.
    public static func bigEmoji(text: String, emoji: [String], spans: [TextSpan], catalog: [String: URL]) -> [URL?] {
        let marks = inline(text: text, spans: spans, catalog: catalog)
        let units = text as NSString
        var cursor = 0
        return emoji.map { item in
            let found = units.range(of: item, range: NSRange(location: cursor, length: max(units.length - cursor, 0)))
            if found.location != NSNotFound { cursor = found.location + found.length }
            if found.location != NSNotFound, let mark = marks.first(where: { $0.from == found.location }) {
                return mark.lottieURL
            }
            return lookup(catalog: catalog, emoji: item)
        }
    }

    /// Ссылка из каталога: точное совпадение или без селектора вида `FE0F`.
    public static func lookup(catalog: [String: URL], emoji: String) -> URL? {
        guard !catalog.isEmpty else { return nil }
        if let hit = catalog[emoji] { return hit }
        let bare = bare(emoji)
        if let hit = catalog[bare] { return hit }
        return catalog.first { Self.bare($0.key) == bare }?.value
    }

    /// Эмодзи без селектора вида `FE0F`.
    public static func bare(_ emoji: String) -> String {
        emoji.replacingOccurrences(of: variation, with: "")
    }

    private static let variation = "\u{FE0F}"
}

/// Анимодзи каталога для чата: эмодзи → Lottie самого эмодзи и эмодзи → эффект реакции.
public struct AnimojiAssets: Sendable, Equatable {
    public var animoji: [String: URL]
    public var effects: [String: URL]

    public init(animoji: [String: URL] = [:], effects: [String: URL] = [:]) {
        self.animoji = animoji
        self.effects = effects
    }

    /// Из каталога сервера; при повторах эмодзи берётся первый.
    public init(_ list: [AnimatedEmoji]) {
        self.init(
            animoji: Dictionary(list.compactMap { item in item.lottieURL.map { (item.emoji, $0) } }, uniquingKeysWith: { first, _ in first }),
            effects: Dictionary(list.compactMap { item in item.effectURL.map { (item.emoji, $0) } }, uniquingKeysWith: { first, _ in first })
        )
    }
}

/// Реакция, которую пользователь только что поставил. Её значок в плашке под сообщением один раз
/// играет анимацию `lottieURL` на месте, а вокруг — эффект `effectURL` (`lottiePlayUrl`
/// анимодзи), крупнее значка; потом значок снова обычный. Так же, как в Komet.
public struct ReactionBurst: Equatable, Sendable {
    public let messageId: String
    public let emoji: String
    public let lottieURL: URL?
    public let effectURL: URL?
    public let id: Int

    public init(messageId: String, emoji: String, lottieURL: URL?, effectURL: URL?, id: Int) {
        self.messageId = messageId
        self.emoji = emoji
        self.lottieURL = lottieURL
        self.effectURL = effectURL
        self.id = id
    }

    /// Это та плашка: то же сообщение и то же эмодзи (без учёта `FE0F`).
    public func matches(messageId: String, emoji: String) -> Bool {
        self.messageId == messageId && AnimojiText.bare(self.emoji) == AnimojiText.bare(emoji)
    }
}
