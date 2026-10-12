import Foundation

/// Measured position and the intention to follow new messages are separate states.
public struct TranscriptBottomState: Equatable, Sendable {
    public private(set) var atBottom = false
    /// Visibility of the last message end is enough to hide the navigation button,
    /// but must not confirm alignment or acknowledge unread messages.
    public private(set) var lastEndVisible = false
    public private(set) var followsLatest = false
    public private(set) var unseen = 0
    public init() {}

    public func showsButton(hasMessages: Bool) -> Bool { hasMessages && !lastEndVisible }

    public mutating func beginFollowing() {
        followsLatest = true
        // Requesting the bottom must not acknowledge unread messages or hide the button.
        atBottom = false
    }
    public mutating func beginReadingHistory() { followsLatest = false; atBottom = false }
    public mutating func userTookOver() { followsLatest = false }

    /// `buttonMin` — верх, от которого конец последней строки прячет кнопку «вниз»: край самой
    /// прокрутки, а не низ шапки. Шапка и плашки над лентой стеклянные, и короткая лента может
    /// заходить под них; кнопка в коротком чате всё равно не нужна.
    public mutating func measuredLastRow(minY: Double?, maxY: Double?, viewportMin: Double, viewportMax: Double, userScrolling: Bool, contentFits: Bool = false, buttonMin: Double? = nil) {
        guard let minY, let maxY,
              [minY, maxY, viewportMin, viewportMax].allSatisfy({ $0.isFinite }),
              maxY > minY, viewportMax > viewportMin else {
            atBottom = false
            lastEndVisible = false
            if userScrolling { followsLatest = false }
            return
        }
        // A short transcript can end above the bottom edge, but the last row must be visible.
        let visible = maxY > viewportMin && minY < viewportMax
        let top = min(viewportMin, buttonMin ?? viewportMin)
        lastEndVisible = maxY > top && maxY <= viewportMax + 24
        atBottom = visible && (abs(maxY - viewportMax) <= 24 || (contentFits && maxY <= viewportMax))
        if atBottom { unseen = 0 }
        if userScrolling { followsLatest = atBottom }
    }

    public mutating func received(_ count: Int) {
        if count > 0 && !atBottom { unseen += count }
    }
}
