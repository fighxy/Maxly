import Foundation
import MaxlyDomain

/// Шапка списка чатов внутри самого списка: первые строки — истории, поиск и
/// папки. Поиск уезжает вместе со списком, папки, дойдя до панели навигации, закрепляются.
/// Истории спрятаны над поиском: список встаёт на поиск, истории открывает потягивание вниз.
///
/// Все координаты — в содержимом списка; `top` — верх его видимой части (под панелью
/// навигации). Диапазоны — где лежат строки историй и поиска, `folders` — верх строки папок.
public struct ChatListHeaderGeometry: Equatable, Sendable {
    /// Насколько истории могут выглядывать, пока у заголовка ещё стопка.
    public static let stackSlack: CGFloat = 8

    public var stories: ClosedRange<CGFloat>?
    public var search: ClosedRange<CGFloat>?
    public var folders: CGFloat?

    public init(stories: ClosedRange<CGFloat>? = nil, search: ClosedRange<CGFloat>? = nil, folders: CGFloat? = nil) {
        self.stories = stories
        self.search = search
        self.folders = folders
    }

    /// Истории спрятаны (или их нет): у заголовка — стопка их аватаров.
    public func storiesHidden(at top: CGFloat) -> Bool {
        guard let stories else { return true }
        return top >= stories.upperBound - Self.stackSlack
    }

    /// Папки дошли до панели навигации: сверху закреплена их копия.
    public func foldersPinned(at top: CGFloat) -> Bool {
        guard let folders else { return false }
        return top >= folders - 0.5
    }

    /// Прокрутка остановилась посреди историй или поиска: куда доехать — к ближнему краю.
    public func snapTarget(at top: CGFloat) -> CGFloat? {
        for range in [stories, search].compactMap({ $0 }) where range.upperBound - range.lowerBound > 1 {
            guard top > range.lowerBound + 0.5, top < range.upperBound - 0.5 else { continue }
            let half = (range.upperBound - range.lowerBound) / 2
            return top - range.lowerBound < half ? range.lowerBound : range.upperBound
        }
        return nil
    }

    /// Инерция сверху вниз по списку долетела до спрятанных историй: она останавливается на
    /// поиске. Истории открывает только палец.
    public func stopsFling(from previous: CGFloat, to top: CGFloat, dragging: Bool, decelerating: Bool) -> Bool {
        guard let stories, !dragging, decelerating else { return false }
        let hidden = stories.upperBound - 0.5
        return previous >= hidden && top < hidden
    }

    /// Где стоять, чтобы истории были спрятаны: верх строки поиска.
    public var storiesHiddenTop: CGFloat? { stories?.upperBound }

    /// Где стоять, чтобы истории были видны целиком.
    public var storiesShownTop: CGFloat? { stories?.lowerBound }
}

/// Кольца историй на аватарах списка.
public enum StoryStripMotion {
    /// Кольцо на аватаре: у человека любое, у группы и канала — только их тип.
    public static func ringMatches(_ ring: StoryRing?, kind: StoryOwner.Kind) -> Bool {
        guard let ring else { return false }
        return ring.owner.kind == kind
    }
}
