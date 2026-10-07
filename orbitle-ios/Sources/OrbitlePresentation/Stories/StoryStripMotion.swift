import Foundation
import OrbitleDomain

/// Жест полосы историй над списком чатов.
/// Палец вверх — отрицательный `drag`. Полоса полностью открыта при доле 1.
/// Список не у верхнего края жест не принимает. Шапка передаёт `atTop: true`.
public enum StoryStripMotion {
    /// Порог в пунктах, после которого отпущенный жест доводится до конца.
    public static let threshold: CGFloat = 48

    public static func reveal(expanded: Bool, drag: CGFloat, height: CGFloat, atTop: Bool) -> CGFloat {
        guard height > 0 else { return expanded ? 1 : 0 }
        guard atTop else { return expanded ? 1 : 0 }
        let base: CGFloat = expanded ? 1 : 0
        let moved: CGFloat = if expanded && drag < 0 {
            drag
        } else if !expanded && drag > 0 {
            drag
        } else {
            0
        }
        return min(1, max(0, base + moved / height))
    }

    /// Каким останется флаг «открыта» после отпускания.
    public static func settledExpanded(wasExpanded: Bool, drag: CGFloat, atTop: Bool, threshold: CGFloat) -> Bool {
        guard atTop else { return wasExpanded }
        return wasExpanded ? drag > -threshold : drag >= threshold
    }

    /// Потянуть список вниз обновляет чаты только у уже открытой полосы.
    public static func refreshesOnPull(expanded: Bool) -> Bool { expanded }

    /// Кольцо на аватаре: у человека любое, у группы и канала — только их тип.
    public static func ringMatches(_ ring: StoryRing?, kind: StoryOwner.Kind) -> Bool {
        guard let ring else { return false }
        return ring.owner.kind == kind
    }
}
