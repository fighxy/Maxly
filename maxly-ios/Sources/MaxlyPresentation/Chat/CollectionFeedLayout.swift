import Foundation

/// Высоты ячеек ленты: у каждой строки своя, из кэша или оценки.
///
/// Секция compositional layout с одним `.estimated` берёт высоту последнего
/// пузыря и растягивает её на всю ленту — короткий текст и медиа прыгают.
/// Flow layout спрашивает высоту по индексу сверху вниз: 0 — самое старое.
public enum CollectionFeedLayout {
    public static func height(
        index: Int,
        chronological: [TranscriptRow],
        maxWidth: Double,
        cache: BubbleHeightCache
    ) -> Double? {
        guard chronological.indices.contains(index) else { return nil }
        return cache.estimated(for: chronological[index], maxWidth: maxWidth)
    }
}

/// Смещение ленты сверху вниз. Новые сообщения внизу, история сверху.
/// Палец и подгрузка держат видимую строку через `contentOffset`, без переворота слоя.
/// Верхний и нижний `contentInset` ленты. Это уже полный зазор: safe area сюда не прибавляется.
public struct FeedChromeInsets: Equatable, Sendable {
    public var top: Double
    public var bottom: Double

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }
}

public enum FeedOffset {
    public static let baseTopInset: Double = 6
    public static let baseBottomInset: Double = 10
    /// Высота inline-шапки под статус-баром, пока низ шапки ещё не измерен.
    public static let fallbackNavigationBar: Double = 54
    /// Высота поля ввода над индикатором «домой», пока его верх ещё не измерен.
    public static let fallbackComposer: Double = 44

    /// Рост строки, которая целиком выше viewport, сдвигает видимые строки вниз.
    /// К смещению прибавляется дельта. Строка, которая ещё пересекает viewport,
    /// сохраняет свой верх — смещение не трогаем.
    public static func compensation(itemMaxY: Double, viewportOffset: Double, heightDelta: Double) -> Double {
        guard heightDelta.isFinite, abs(heightDelta) >= 2, itemMaxY <= viewportOffset + 1 else { return 0 }
        return heightDelta
    }

    public static func clamped(_ raw: Double, min minOffset: Double, max maxOffset: Double) -> Double {
        guard raw.isFinite, minOffset.isFinite, maxOffset.isFinite else { return minOffset }
        if maxOffset < minOffset { return minOffset }
        return min(max(raw, minOffset), maxOffset)
    }

    /// Верх строки остаётся на том же расстоянии от верха viewport.
    public static func restoring(rowMinY: Double, topInViewport: Double, minOffset: Double, maxOffset: Double) -> Double {
        clamped(rowMinY - topInViewport, min: minOffset, max: maxOffset)
    }

    /// `anchor` 0 — верх строки у верха видимой области, 1 — низ строки у её низа.
    public static func revealing(
        rowMinY: Double,
        rowHeight: Double,
        anchor: Double,
        viewportHeight: Double,
        insetTop: Double,
        minOffset: Double,
        maxOffset: Double
    ) -> Double {
        let placed = min(1, max(0, anchor))
        let rowPoint = rowMinY + max(0, rowHeight) * placed
        let viewPoint = insetTop + max(0, viewportHeight) * placed
        return clamped(rowPoint - viewPoint, min: minOffset, max: maxOffset)
    }

    /// Шапка, пока её низ не измерен. Safe area, в которой уже есть панель навигации, не дополняется второй.
    public static func unresolvedHeader(safeTop: Double, windowTop: Double) -> Double {
        let safe = nonNegative(safeTop)
        let window = nonNegative(windowTop)
        if safe > 0, safe >= window + fallbackNavigationBar * 0.5 { return safe }
        return max(safe, window) + fallbackNavigationBar
    }

    /// Поле ввода, пока его верх не измерен. Большой нижний safe area уже включает поле ввода.
    public static func unresolvedComposer(safeBottom: Double, windowBottom: Double) -> Double {
        let safe = nonNegative(safeBottom)
        let window = nonNegative(windowBottom)
        if safe > window + fallbackComposer * 0.5 { return safe }
        return max(safe, window) + fallbackComposer
    }

    /// Насколько шапка перекрывает саму ленту. Лента, уже стоящая ниже шапки, не получает второй верхний зазор.
    public static func headerOverlap(
        frameMinY: Double,
        frameMaxY: Double,
        headerBottom: Double?,
        unresolved: Double
    ) -> Double {
        guard frameMaxY.isFinite, frameMinY.isFinite, frameMaxY > frameMinY else { return nonNegative(unresolved) }
        if let headerBottom, headerBottom.isFinite, headerBottom > 0 {
            return max(0, min(frameMaxY, headerBottom) - frameMinY)
        }
        return max(0, nonNegative(unresolved) - max(0, frameMinY))
    }

    /// Насколько поле ввода перекрывает ленту. Лента, уже кончающаяся у поля, не получает второй нижний зазор.
    public static func composerOverlap(
        frameMinY: Double,
        frameMaxY: Double,
        frameReachesScreenBottom: Bool,
        composerTop: Double?,
        unresolved: Double
    ) -> Double {
        guard frameMaxY.isFinite, frameMinY.isFinite, frameMaxY > frameMinY else { return nonNegative(unresolved) }
        if let composerTop, composerTop.isFinite, composerTop > 0 {
            return max(0, frameMaxY - max(frameMinY, composerTop))
        }
        return frameReachesScreenBottom ? nonNegative(unresolved) : 0
    }

    /// Полный content inset. Короткая лента получает запас сверху и садится на поле ввода.
    /// Длинная оставляет перекрытие шапки и поля плюс небольшой зазор. Safe area повторно не входит.
    public static func chromeInsets(
        boundsHeight: Double,
        contentHeight: Double,
        headerOverlap: Double,
        composerOverlap: Double,
        topPadding: Double = baseTopInset,
        bottomPadding: Double = baseBottomInset
    ) -> FeedChromeInsets {
        let minimumTop = nonNegative(headerOverlap) + nonNegative(topPadding)
        let bottom = nonNegative(composerOverlap) + nonNegative(bottomPadding)
        guard boundsHeight > 1, contentHeight > 1, boundsHeight.isFinite, contentHeight.isFinite else {
            return FeedChromeInsets(top: minimumTop, bottom: bottom)
        }
        let visible = boundsHeight - minimumTop - bottom
        let extra = max(0, visible - contentHeight)
        return FeedChromeInsets(top: minimumTop + extra, bottom: bottom)
    }

    /// Расстояние от низа строки до читаемого низа (выше поля ввода).
    public static func distanceAboveCover(rowMaxY: Double, viewportMaxY: Double, cover: Double) -> Double {
        guard rowMaxY.isFinite, viewportMaxY.isFinite else { return 0 }
        return max(0, viewportMaxY - nonNegative(cover) - rowMaxY)
    }

    public static func contentFits(
        contentHeight: Double,
        boundsHeight: Double,
        insetTop: Double,
        insetBottom: Double
    ) -> Bool {
        guard boundsHeight > 1, contentHeight > 1 else { return false }
        return contentHeight <= boundsHeight - insetTop - insetBottom + 1
    }

    static func nonNegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

/// Куда встать после смены строк. Палец важнее прилипания к низу.
public enum FeedSettlePlan: Equatable, Sendable {
    /// Последняя строка у нижнего края.
    case pinBottom
    /// Явная цель (непрочитанное, цитата, поиск).
    case reveal
    /// Видимая строка остаётся на месте.
    case restore
    /// Смещение не трогаем.
    case keep
}

public enum FeedSettle {
    public static func plan(
        interacting: Bool,
        contentFits: Bool,
        stickToBottom: Bool,
        hasHistoryReveal: Bool,
        pinToLatest: Bool,
        hasAnchor: Bool
    ) -> FeedSettlePlan {
        if interacting { return hasAnchor ? .restore : .keep }
        if contentFits { return .pinBottom }
        if hasHistoryReveal { return .reveal }
        if stickToBottom || pinToLatest { return .pinBottom }
        if hasAnchor { return .restore }
        return .keep
    }
}
