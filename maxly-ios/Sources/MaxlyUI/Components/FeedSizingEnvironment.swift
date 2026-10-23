import SwiftUI

private struct FeedSizingKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Строка ленты собрана только для замера высоты вне экрана, до показа. Раскладка та же,
    /// а побочного нет: рамки медиа не регистрируются для просмотра, гифки и кружки не играют.
    var isFeedSizing: Bool {
        get { self[FeedSizingKey.self] }
        set { self[FeedSizingKey.self] = newValue }
    }
}
