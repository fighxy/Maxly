import Foundation

/// Высота панели эмодзи, стикеров и GIF после того, как её отпустили: на месте клавиатуры,
/// вытянутая почти на весь экран или закрытая.
public enum StickerPanelDetent: Equatable, Sendable {
    case collapsed
    case expanded
    case closed

    /// Куда встанет панель. `translation` и `predicted` — сдвиг пальца вверх (вниз — меньше нуля)
    /// и куда его донесла бы инерция. Панель встаёт к ближайшей высоте по инерции; вниз
    /// заметно ниже клавиатурной она закрывается, но вытянутая сначала встаёт на место
    /// клавиатуры: одно движение не закрывает её из-под пальца.
    public static func settle(
        expanded: Bool,
        collapsedHeight: Double,
        expandedHeight: Double,
        translation: Double,
        predicted: Double
    ) -> StickerPanelDetent {
        let base = expanded ? expandedHeight : collapsedHeight
        let landing = base + predicted
        if !expanded, base + translation < collapsedHeight - closeDistance || landing < collapsedHeight - 2 * closeDistance {
            return .closed
        }
        return landing > (collapsedHeight + expandedHeight) / 2 ? .expanded : .collapsed
    }

    /// Высота под пальцем: не ниже половины клавиатурной и не выше вытянутой.
    public static func height(expanded: Bool, collapsedHeight: Double, expandedHeight: Double, translation: Double) -> Double {
        let base = expanded ? expandedHeight : collapsedHeight
        return min(max(base + translation, collapsedHeight / 2), expandedHeight)
    }

    /// Насколько ниже клавиатурной высоты нужно стянуть панель, чтобы она закрылась.
    static let closeDistance: Double = 80
}
