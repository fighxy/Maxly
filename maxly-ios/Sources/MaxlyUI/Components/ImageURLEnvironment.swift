import SwiftUI
import MaxlyDomain

private struct ImageURLSizingKey: EnvironmentKey {
    static let defaultValue: any ImageURLSizing = PassthroughImageURLSizing()
}

public extension EnvironmentValues {
    /// Выбор `fn` у аватаров и миниатюр. По умолчанию адрес не меняется.
    var imageURLSizing: any ImageURLSizing {
        get { self[ImageURLSizingKey.self] }
        set { self[ImageURLSizingKey.self] = newValue }
    }
}
