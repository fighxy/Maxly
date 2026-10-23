import Foundation
import MaxlyDomain

/// Оценка высоты строки ленты до раскладки SwiftUI/UIKit.
///
/// Нативные мессенджеры кладут в UICollectionView уже посчитанный размер.
/// Здесь — быстрая эвристика по содержимому. Collection feed берёт высоту
/// каждой строки (`CollectionFeedLayout`), а не одну оценку на всю секцию.
/// Класс: мутации из `@State` / UIKit-координатора без копирования словаря.
public final class BubbleHeightCache: @unchecked Sendable {
    public static let rowSpacing: Double = 2
    public static let daySeparator: Double = 28
    public static let unreadSeparator: Double = 28
    public static let authorName: Double = 18
    public static let avatarGutter: Double = 40
    public static let bubblePaddingY: Double = 16
    public static let lineHeight: Double = 22
    public static let minTextBubble: Double = 36
    public static let mediaTile: Double = 180
    public static let voice: Double = 56
    public static let file: Double = 64
    public static let sticker: Double = 160
    public static let reactionRow: Double = 28
    public static let service: Double = 32
    public static let reply: Double = 52
    public static let forward: Double = 36
    public static let pollTitle: Double = 28
    public static let pollAnswer: Double = 40
    public static let pollFooter: Double = 24
    public static let linkPreview: Double = 88
    public static let contactCard: Double = 72
    public static let callRow: Double = 64
    public static let keyboardRow: Double = 44
    public static let commentsFooter: Double = 36
    /// Горизонтальные поля текста и место под время, чтобы перенос не занижал высоту.
    public static let textHorizontalChrome: Double = 36

    private var heights: [String: Double] = [:]
    private let lock = NSLock()

    /// Точная высота текста (points). Ставит MaxlyUI `BubbleTextMeasurer.installAsHeightProvider`.
    /// Меняется только при старте приложения / в тестах — как `Log.sink`.
    nonisolated(unsafe) public static var textHeightProvider: (@Sendable (String, Double) -> Double)?

    public init() {}

    public subscript(id: String) -> Double? {
        get {
            lock.lock(); defer { lock.unlock() }
            return heights[id]
        }
        set {
            lock.lock(); defer { lock.unlock() }
            heights[id] = newValue
        }
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        heights.removeAll(keepingCapacity: true)
    }

    /// Запомнить измеренную высоту после layout (points).
    public func store(id: String, height: Double) {
        guard height.isFinite, height > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        heights[id] = height
    }

    /// Оценка до раскладки. Не затирает высоту, которую уже замерила ячейка.
    public func storeIfAbsent(id: String, height: Double) {
        guard height.isFinite, height > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if heights[id] == nil { heights[id] = height }
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        heights[id] = nil
    }

    public func estimated(for row: TranscriptRow, maxWidth: Double) -> Double {
        lock.lock()
        let cached = heights[row.id]
        lock.unlock()
        if let cached { return cached }
        return Self.estimate(row: row, maxWidth: maxWidth)
    }

    public static func estimate(row: TranscriptRow, maxWidth: Double) -> Double {
        var total = 0.0
        if row.dayTitle != nil { total += daySeparator }
        if row.startsUnread { total += unreadSeparator }
        if row.message.content.isService {
            return total + service
        }
        if row.showsAuthorName { total += authorName }
        total += contentHeight(row.message, maxWidth: max(1, maxWidth))
        if !row.message.content.reactions.isEmpty { total += reactionRow }
        return max(total, minTextBubble)
    }

    private static func contentHeight(_ message: Message, maxWidth: Double) -> Double {
        let content = message.content
        var height = bubblePaddingY
        if !content.visuals.isEmpty {
            let columns = min(2, content.visuals.count)
            let rows = Int(ceil(Double(content.visuals.count) / Double(columns)))
            height += Double(rows) * mediaTile
        }
        if !content.voices.isEmpty {
            height += Double(content.voices.count) * voice
        }
        if !content.files.isEmpty {
            height += Double(content.files.count) * file
        }
        if content.sticker != nil {
            height += sticker
        }
        if !content.contacts.isEmpty {
            height += Double(content.contacts.count) * contactCard
        }
        if !content.calls.isEmpty {
            height += Double(content.calls.count) * callRow
        }
        if let poll = content.poll {
            height += pollTitle + Double(max(1, poll.answers.count)) * pollAnswer + pollFooter
        }
        if content.reply != nil { height += reply }
        if content.forward != nil { height += forward }
        if content.linkPreview != nil { height += linkPreview }
        if let rows = content.keyboard?.rows, !rows.isEmpty {
            height += Double(rows.count) * keyboardRow
        }
        if content.comments != nil { height += commentsFooter }
        let text = message.displayText
        if !text.isEmpty {
            let textWidth = max(40, maxWidth - textHorizontalChrome)
            if let provider = textHeightProvider {
                height += provider(text, textWidth)
            } else {
                let charsPerLine = max(12.0, textWidth / 8.5)
                let lines = max(1.0, ceil(Double(text.count) / charsPerLine))
                height += lines * lineHeight
            }
        }
        if height <= bubblePaddingY {
            height += minTextBubble
        }
        return height
    }
}
