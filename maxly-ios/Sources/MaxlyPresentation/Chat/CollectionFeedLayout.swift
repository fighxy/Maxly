import Foundation

/// Высоты ячеек ленты: у каждой строки своя, из кэша или оценки.
///
/// Секция compositional layout с одним `.estimated` берёт высоту последнего
/// пузыря и растягивает её на всю ленту — короткий текст и медиа прыгают.
/// Flow layout спрашивает высоту по хронологическому индексу: 0 — самое старое.
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

/// Бегунок скролла вне `scaleY(-1)`: offset 0 — визуальный низ, бегунок внизу дорожки.
public struct InvertedThumbFrame: Equatable, Sendable {
    public var hidden: Bool
    public var y: Double
    public var height: Double

    public static func make(
        offset: Double,
        content: Double,
        viewport: Double,
        track: Double,
        minThumb: Double = 28
    ) -> InvertedThumbFrame {
        guard content.isFinite, viewport.isFinite, track.isFinite,
              content > viewport + 1, viewport > 1, track > 1 else {
            return InvertedThumbFrame(hidden: true, y: 0, height: 0)
        }
        let thumb = min(track, max(minThumb, track * (viewport / content)))
        let maxOffset = content - viewport
        let progress = min(1, max(0, offset / maxOffset))
        let y = (track - thumb) * (1 - progress)
        return InvertedThumbFrame(hidden: false, y: y, height: thumb)
    }
}

/// Порядок VoiceOver сверху вниз. В data source секция 0 и item 0 — визуальный низ.
public struct FeedIndexPath: Equatable, Sendable {
    public var section: Int
    public var item: Int

    public init(section: Int, item: Int) {
        self.section = section
        self.item = item
    }
}

public enum InvertedAccessibilityOrder {
    public static func topToBottom(_ paths: [FeedIndexPath]) -> [FeedIndexPath] {
        paths.sorted { lhs, rhs in
            if lhs.section != rhs.section { return lhs.section > rhs.section }
            return lhs.item > rhs.item
        }
    }
}

/// Поправка contentOffset, когда высота ячейки ближе к визуальному низу меняется,
/// а читатель смотрит историю: кадры выше по контенту сдвигаются, offset — нет.
public enum MeasuredOffsetCompensation {
    public static func delta(itemMaxY: Double, viewportOffset: Double, heightDelta: Double) -> Double {
        guard heightDelta.isFinite, abs(heightDelta) >= 2, itemMaxY <= viewportOffset + 1 else { return 0 }
        return heightDelta
    }
}
