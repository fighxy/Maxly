import Foundation
import OrbitleDomain

/// Полоса историй в шапке списка чатов, как в Telegram.
///
/// Свёрнута по умолчанию: у заголовка «Чаты» видна стопка из нескольких аватаров с кольцами.
/// Раскрывается, если потянуть список вниз от верха (палец на экране) или коснуться стопки.
/// Сворачивается, когда список уезжает вверх — пальцем или по инерции.
///
/// `gap` — где верх списка относительно низа шапки: больше нуля — список потянут вниз,
/// меньше — уехал под шапку, `nil` — верх списка давно за экраном. Меряется по экрану, а не по
/// смещению прокрутки, поэтому не зависит от того, как прокрутка считает отступы.
///
/// Раскрытая или свёрнутая полоса меняет высоту шапки, и список под ней сдвигается. Чтобы этот
/// сдвиг не переключил полосу обратно, после каждого переключения жест до конца ничего не
/// меняет (`settling`); следующий — уже по обычным правилам.
public struct StoryStripMotion: Equatable, Sendable {
    /// Насколько потянуть список вниз, чтобы раскрыть полосу.
    public static let pullToExpand: CGFloat = 64
    /// Насколько список должен уехать под шапку, чтобы полоса свернулась.
    public static let scrollToCollapse: CGFloat = 24

    public enum Change: Equatable, Sendable {
        case none
        case expand
        case collapse
    }

    public private(set) var expanded: Bool
    /// После переключения: до конца этого жеста полоса не переключается.
    public private(set) var settling = false

    public init(expanded: Bool = false) {
        self.expanded = expanded
    }

    /// Список сдвинулся. `dragging` — палец на списке, `decelerating` — инерция после него.
    /// Раскрывает только палец: долёт по инерции до верха полосу не открывает.
    public mutating func moved(gap: CGFloat?, dragging: Bool, decelerating: Bool, hasStories: Bool) -> Change {
        guard hasStories else { return collapseIfNeeded() }
        guard !settling, dragging || decelerating else { return .none }
        let position = gap ?? -.infinity
        if !expanded, dragging, position >= Self.pullToExpand {
            expanded = true
            settling = true
            return .expand
        }
        if expanded, position <= -Self.scrollToCollapse {
            expanded = false
            settling = true
            return .collapse
        }
        return .none
    }

    /// Прокрутка остановилась: следующий жест снова переключает полосу.
    public mutating func scrollEnded() {
        settling = false
    }

    /// Касание стопки у заголовка или самого заголовка.
    public mutating func toggle(hasStories: Bool) -> Change {
        guard hasStories || expanded else { return .none }
        expanded.toggle()
        return expanded ? .expand : .collapse
    }

    private mutating func collapseIfNeeded() -> Change {
        guard expanded else { return .none }
        expanded = false
        return .collapse
    }

    /// Кольцо на аватаре: у человека любое, у группы и канала — только их тип.
    public static func ringMatches(_ ring: StoryRing?, kind: StoryOwner.Kind) -> Bool {
        guard let ring else { return false }
        return ring.owner.kind == kind
    }
}
