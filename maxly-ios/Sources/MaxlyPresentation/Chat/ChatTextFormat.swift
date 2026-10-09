import Foundation
import MaxlyDomain

/// Кусок текста пузыря: обычный абзац или цитата. Отрезки форматирования внутри блока
/// отсчитываются от его начала (UTF-16).
public struct TextBlock: Hashable, Sendable {
    public var text: String
    public var isQuote: Bool
    public var spans: [TextSpan]

    public init(text: String, isQuote: Bool, spans: [TextSpan]) {
        self.text = text
        self.isQuote = isQuote
        self.spans = spans
    }
}

/// Разметка текста сообщения без SwiftUI, чтобы её проверяли тесты.
public enum ChatTextFormat {
    /// Текст делится на блоки по цитатам (`QUOTE`): цитата рисуется отдельной плашкой с полосой.
    /// Отрезки за пределами текста обрезаются, пустые блоки и переводы строк на стыках убираются.
    public static func blocks(text: String, spans: [TextSpan]) -> [TextBlock] {
        let units = Array(text.utf16)
        let count = units.count
        let clamped = spans.compactMap { span -> TextSpan? in
            let start = min(max(span.from, 0), count)
            let end = min(max(span.from + span.length, start), count)
            guard end > start else { return nil }
            var copy = span
            copy.from = start
            copy.length = end - start
            return copy
        }
        let quotes = clamped.filter { $0.kind == .quote }.sorted { $0.from < $1.from }
        let inline = clamped.filter { $0.kind != .quote }

        var ranges: [(Range<Int>, Bool)] = []
        var cursor = 0
        for quote in quotes {
            let start = max(quote.from, cursor)
            let end = quote.from + quote.length
            guard end > start else { continue }
            if start > cursor { ranges.append((cursor..<start, false)) }
            ranges.append((start..<end, true))
            cursor = end
        }
        if cursor < count || ranges.isEmpty { ranges.append((cursor..<count, false)) }

        return ranges.compactMap { range, isQuote in
            var lower = range.lowerBound
            var upper = range.upperBound
            // Переводы строк на границе с цитатой дают лишний пустой абзац.
            while lower < upper, units[lower] == 0x0A { lower += 1 }
            while upper > lower, units[upper - 1] == 0x0A { upper -= 1 }
            guard upper > lower || (ranges.count == 1 && !isQuote) else { return nil }
            let piece = String(utf16CodeUnits: Array(units[lower..<upper]), count: upper - lower)
            let local = inline.compactMap { span -> TextSpan? in
                let start = max(span.from, lower)
                let end = min(span.from + span.length, upper)
                guard end > start else { return nil }
                var copy = span
                copy.from = start - lower
                copy.length = end - start
                return copy
            }
            return TextBlock(text: piece, isQuote: isQuote, spans: local)
        }
    }
}
