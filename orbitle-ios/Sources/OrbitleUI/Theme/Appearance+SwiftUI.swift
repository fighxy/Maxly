import SwiftUI
import OrbitleDomain

public extension TextSizeStep {
    /// Размер Dynamic Type для корня приложения: по нему масштабируются стили текста
    /// (`.body`, `.subheadline`…) и `@ScaledMetric` во всех экранах.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        }
    }
}
