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
public enum FeedOffset {
    public static let baseTopInset: Double = 6
    public static let baseBottomInset: Double = 10

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

    /// Верхний content inset. Короткая лента получает запас сверху и садится на поле ввода.
    /// Длинная оставляет только базовый зазор.
    public static func shortTopInset(
        boundsHeight: Double,
        safeTop: Double,
        safeBottom: Double,
        contentHeight: Double,
        baseTop: Double = baseTopInset,
        baseBottom: Double = baseBottomInset
    ) -> Double {
        guard boundsHeight > 1, contentHeight > 1,
              [safeTop, safeBottom, baseTop, baseBottom].allSatisfy(\.isFinite) else { return baseTop }
        let available = boundsHeight - safeTop - safeBottom - baseTop - baseBottom
        return baseTop + max(0, available - contentHeight)
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
