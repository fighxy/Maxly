import Foundation

/// Кнопка «вниз» по настоящей геометрии прокрутки: расстояние от видимого низа до конца
/// содержимого с учётом нижнего отступа (поле ввода, клавиатура, безопасная зона).
/// Рамки отдельных строк для этого ненадёжны: последняя строка ленивой ленты может быть
/// не измерена, а её низ — под стеклом поля ввода ниже измеренной видимой области.
/// Гистерезис: кнопка появляется, когда ленту увели вверх больше чем на `showFraction`
/// высоты экрана (не меньше `minShow`), и прячется, когда до низа осталось `hide` и меньше.
public struct ScrollDownVisibility: Equatable, Sendable {
    public private(set) var shown = false
    public var hide: Double = 48
    public var minShow: Double = 200
    public var showFraction: Double = 0.75
    public init() {}

    /// Расстояние до низа в точках; `0` и меньше — у самого низа (или отскок ниже него).
    public static func distanceFromBottom(contentHeight: Double, offsetY: Double, viewportHeight: Double,
                                          insetTop: Double, insetBottom: Double) -> Double {
        let values = [contentHeight, offsetY, viewportHeight, insetTop, insetBottom]
        guard values.allSatisfy({ $0.isFinite }), viewportHeight > 0 else { return 0 }
        // Наибольшее смещение: конец содержимого вместе с нижним отступом у низа экрана.
        // Содержимое короче экрана прокручивать некуда — смещение остаётся у верха.
        let maxOffset = max(-insetTop, contentHeight + insetBottom - viewportHeight)
        return max(0, maxOffset - offsetY)
    }

    /// Возвращает `true`, если видимость кнопки сменилась.
    @discardableResult
    public mutating func update(distance: Double, visibleHeight: Double) -> Bool {
        guard distance.isFinite else { return false }
        let threshold = max(minShow, (visibleHeight.isFinite ? max(0, visibleHeight) : 0) * showFraction)
        let next: Bool
        if shown { next = distance > hide } else { next = distance > threshold }
        guard next != shown else { return false }
        shown = next
        return true
    }

    /// Переход к низу или открытие чата у низа: кнопка сразу прячется.
    public mutating func reset() { shown = false }
}
