import SwiftUI

public extension Color {
    static let orbitlAccent = Color(red: 0.36, green: 0.42, blue: 0.96)
    static let orbitlOutgoing = Color(red: 0.36, green: 0.42, blue: 0.96)
    /// Синий круг «Избранного» и архива.
    static let orbitlSpecialAvatar = Color(red: 0.30, green: 0.62, blue: 0.98)
    static let orbitlOnline = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// Серый бейдж чата без звука.
    static let orbitlMutedBadge = Color.gray.opacity(0.55)
    #if os(iOS)
    static let orbitlIncoming = Color(uiColor: .secondarySystemBackground)
    /// Подложка плоского поля поиска.
    static let orbitlField = Color(uiColor: .tertiarySystemFill)
    /// Чуть серый фон закреплённых строк.
    static let orbitlPinnedBackground = Color(uiColor: .secondarySystemBackground)
    static let orbitlBackground = Color(uiColor: .systemBackground)
    #else
    static let orbitlIncoming = Color(red: 0.93, green: 0.93, blue: 0.95)
    static let orbitlField = Color.gray.opacity(0.12)
    static let orbitlPinnedBackground = Color.gray.opacity(0.08)
    static let orbitlBackground = Color.white
    #endif
}

/// Градиенты аватаров без фото. Номер цвета даёт `ChatAvatar.colorIndex(for:)`.
public enum AvatarPalette {
    public static let gradients: [(top: Color, bottom: Color)] = [
        (Color(red: 1.00, green: 0.53, blue: 0.45), Color(red: 0.93, green: 0.33, blue: 0.33)), // красный
        (Color(red: 1.00, green: 0.75, blue: 0.40), Color(red: 0.98, green: 0.56, blue: 0.20)), // оранжевый
        (Color(red: 0.73, green: 0.60, blue: 1.00), Color(red: 0.55, green: 0.40, blue: 0.93)), // фиолетовый
        (Color(red: 0.55, green: 0.87, blue: 0.45), Color(red: 0.33, green: 0.72, blue: 0.32)), // зелёный
        (Color(red: 0.45, green: 0.87, blue: 0.87), Color(red: 0.22, green: 0.70, blue: 0.75)), // бирюзовый
        (Color(red: 0.47, green: 0.75, blue: 1.00), Color(red: 0.27, green: 0.55, blue: 0.93)), // синий
        (Color(red: 1.00, green: 0.55, blue: 0.75), Color(red: 0.90, green: 0.35, blue: 0.58)), // розовый
    ]

    public static func gradient(_ index: Int) -> LinearGradient {
        let pair = gradients[((index % gradients.count) + gradients.count) % gradients.count]
        return LinearGradient(colors: [pair.top, pair.bottom], startPoint: .top, endPoint: .bottom)
    }
}
