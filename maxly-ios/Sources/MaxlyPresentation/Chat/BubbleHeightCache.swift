import Foundation
import MaxlyDomain

/// Оценка высоты строки ленты по содержимому, до раскладки SwiftUI/UIKit.
///
/// Лента на UICollectionView берёт оценку только для строк далеко от экрана
/// (`FeedHeightStore`): строки у экрана меряются точно до показа. Хранилище высот здесь —
/// для запасного пути `LazyVStack`.
/// Класс: мутации из `@State` без копирования словаря.
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
    public static let keyboardRow: Double = 40
    public static let commentsFooter: Double = 36

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

    /// Оценка строки ленты по содержимому. `maxWidth` — ширина колонки пузыря (`TranscriptBubble`
    /// `maxWidth`), `reservesAvatar` — в группе слева место под аватар входящих.
    /// `textHeight` — высота текста по ширине строки; по умолчанию TextKit из MaxlyUI.
    public static func estimate(
        row: TranscriptRow,
        maxWidth: Double,
        reservesAvatar: Bool = false,
        textHeight: (@Sendable (String, Double) -> Double)? = textHeightProvider
    ) -> Double {
        var total = 0.0
        if row.dayTitle != nil { total += daySeparator }
        if row.startsUnread { total += unreadSeparator }
        if row.message.content.isService {
            return total + service
        }
        if row.showsAuthorName { total += authorName }
        let bubbleWidth = BubbleMetrics.bubbleWidth(
            maxWidth: max(1, maxWidth),
            reservesAvatar: reservesAvatar && !row.isOutgoing
        )
        total += contentHeight(
            row.message,
            bubbleWidth: bubbleWidth,
            outgoing: row.isOutgoing,
            showsAuthorName: row.showsAuthorName,
            showsKeyboard: row.showsKeyboard,
            textHeight: textHeight
        )
        if !row.message.content.reactions.isEmpty { total += reactionRow }
        return max(total, minTextBubble)
    }

    private static func contentHeight(
        _ message: Message,
        bubbleWidth: Double,
        outgoing: Bool,
        showsAuthorName: Bool,
        showsKeyboard: Bool,
        textHeight: (@Sendable (String, Double) -> Double)?
    ) -> Double {
        let content = message.content
        let layout = MessageBubbleLayout(message: message, showsAuthorName: showsAuthorName, showsComments: content.comments != nil)
        var height = bubblePaddingY
        height += mediaHeight(content, bubbleWidth: bubbleWidth, hasFill: layout.hasFill)
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
        if showsKeyboard, let rows = content.keyboard?.rows, !rows.isEmpty {
            height += Double(rows.count) * keyboardRow
        }
        if content.comments != nil { height += commentsFooter }
        let text = message.displayText
        if !text.isEmpty {
            // Время с галочками стоит в конце последней строки: если строка полная, оно
            // переносит её. Место под время меряется вместе с текстом, как его резервирует пузырь.
            let reserve = layout.metadata == .text ? BubbleMetrics.timeReserve(outgoing: outgoing) : ""
            let width = BubbleMetrics.textWidth(bubbleWidth: columnWidth(content, bubbleWidth: bubbleWidth, hasFill: layout.hasFill))
            if let textHeight {
                height += textHeight(text + reserve, width)
            } else {
                let charsPerLine = max(12.0, width / 8.5)
                let lines = max(1.0, ceil(Double(text.count + reserve.count) / charsPerLine))
                height += lines * lineHeight
            }
        }
        if height <= bubblePaddingY {
            height += minTextBubble
        }
        return height
    }

    /// Ширина колонки пузыря: одиночный кадр над подписью задаёт её сам (`captionedTile`),
    /// иначе — вся ширина пузыря.
    static func columnWidth(_ content: MessageContent, bubbleWidth: Double, hasFill: Bool) -> Double {
        let visuals = content.visuals
        guard hasFill, visuals.count == 1, visuals[0].video?.isRound != true else { return bubbleWidth }
        let inset = BubbleMetrics.mediaInset
        let tile = ChatContentFormat.captionedTile(aspect: BubbleMetrics.aspect(visuals[0]), width: max(1, bubbleWidth - inset * 2))
        return tile.width + inset * 2
    }

    /// Фото и видео той же раскладкой, что рисует пузырь (`MediaMosaic`): одиночный кадр у
    /// подписи — `captionedTile`, иначе альбом рядами, кружок своим диаметром.
    static func mediaHeight(_ content: MessageContent, bubbleWidth: Double, hasFill: Bool) -> Double {
        let visuals = content.visuals
        guard !visuals.isEmpty else { return 0 }
        let inset = hasFill ? BubbleMetrics.mediaInset : 0
        let width = max(1, bubbleWidth - inset * 2)
        let round = visuals.count == 1 && visuals[0].video?.isRound == true
        let aspects = visuals.map(BubbleMetrics.aspect)
        let album: AlbumLayout
        if hasFill, visuals.count == 1, !round {
            album = ChatContentFormat.captionedTile(aspect: aspects[0], width: width)
        } else {
            album = ChatContentFormat.album(
                aspects: aspects,
                maxWidth: round ? min(width, BubbleMetrics.roundSide) : width,
                maxHeight: hasFill && !round ? 620 : 360
            )
        }
        return album.height + inset * 2
    }
}

/// Размеры пузыря, от которых зависит перенос текста и ширина медиа. Те же числа, что у
/// `MessageBubble`: колонка пузыря уже `maxWidth` на аватар в группе, текст — на поля пузыря.
public enum BubbleMetrics {
    public static let avatarSize: Double = 34
    public static let avatarSpacing: Double = 6
    public static let minBubbleWidth: Double = 140
    /// Поле текста слева и справа внутри пузыря.
    public static let textInset: Double = 12
    /// Отступ медиа от края пузыря с подложкой.
    public static let mediaInset: Double = 3
    /// Диаметр кружка в ленте.
    public static let roundSide: Double = 220

    /// Ширина колонки пузыря. Во входящих группы слева место под аватар автора.
    public static func bubbleWidth(maxWidth: Double, reservesAvatar: Bool) -> Double {
        max(minBubbleWidth, maxWidth - (reservesAvatar ? avatarSize + avatarSpacing : 0))
    }

    /// Ширина строки текста: колонка пузыря без его полей.
    public static func textWidth(bubbleWidth: Double) -> Double {
        max(40, bubbleWidth - textInset * 2)
    }

    /// Знаки того же объёма, что место под время и галочки в конце текста: перенос строки
    /// при оценке совпадает с тем, что нарисует пузырь.
    public static func timeReserve(outgoing: Bool) -> String {
        outgoing ? "\u{00A0}0000000" : "\u{00A0}00000"
    }

    /// Пропорция кадра по размерам из сервера; неизвестные — квадрат, кружок — всегда квадрат.
    public static func aspect(_ item: ChatAttachment) -> Double {
        if item.video?.isRound == true { return 1 }
        let pixels = item.photo.map { ($0.width, $0.height) } ?? item.video.map { ($0.width, $0.height) }
        guard let width = pixels?.0, let height = pixels?.1, width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}
