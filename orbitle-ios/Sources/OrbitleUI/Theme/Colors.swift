import SwiftUI

public extension Color {
    /// Синий акцент действий и контрастный текст на его заливке.
    static let orbitleAccent = adaptive(light: 0x0070E0, dark: 0x64B5F6)
    static let orbitleOnAccent = adaptive(light: 0xFFFFFF, dark: 0x102030)

    /// Спокойные поверхности чата: серо-голубой фон ленты, белые входящие и светло-зелёные
    /// исходящие (в тёмной теме — тёмные и приглушённые синие); текст и контролы имеют свои токены.
    static let orbitleChatBackground = adaptive(light: 0xE9EEF2, dark: 0x101A24)
    static let orbitleOutgoing = adaptive(light: 0xE1FFC7, dark: 0x2B5278)
    static let orbitleOutgoingText = adaptive(light: 0x15251A, dark: 0xFFFFFF)
    static let orbitleOutgoingSecondary = adaptive(light: 0x48643F, dark: 0xC0D4E5)
    static let orbitleOutgoingAccent = adaptive(light: 0x356B37, dark: 0xC0E1FF)
    static let orbitleOnOutgoingAccent = adaptive(light: 0xFFFFFF, dark: 0x18344D)
    /// Синий круг «Избранного» и архива.
    static let orbitleSpecialAvatar = Color(red: 0.30, green: 0.62, blue: 0.98)
    static let orbitleOnline = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// Серый бейдж чата без звука.
    static let orbitleMutedBadge = Color.gray.opacity(0.55)
    #if os(iOS)
    static let orbitleIncoming = adaptive(light: 0xFFFFFF, dark: 0x182533)
    static let orbitleIncomingOnWallpaper = orbitleIncoming
    /// Подложка плоского поля поиска.
    static let orbitleField = Color(uiColor: .tertiarySystemFill)
    /// Чуть серый фон закреплённых строк.
    static let orbitlePinnedBackground = Color(uiColor: .secondarySystemBackground)
    static let orbitleBackground = Color(uiColor: .systemBackground)
    #else
    static let orbitleIncoming = adaptive(light: 0xFFFFFF, dark: 0x182533)
    static let orbitleIncomingOnWallpaper = orbitleIncoming
    static let orbitleField = Color.gray.opacity(0.12)
    static let orbitlePinnedBackground = Color.gray.opacity(0.08)
    static let orbitleBackground = Color.white
    #endif

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func components(_ value: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((value >> 16) & 0xFF) / 255,
             CGFloat((value >> 8) & 0xFF) / 255,
             CGFloat(value & 0xFF) / 255)
        }
        let day = components(light)
        let night = components(dark)
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? night : day
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #endif
    }

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

    /// Цвет имени автора в группе: тот же тон, что у его аватара без фото.
    public static func nameColor(_ index: Int) -> Color {
        gradients[((index % gradients.count) + gradients.count) % gradients.count].bottom
    }

    public static func gradient(_ index: Int) -> LinearGradient {
        let pair = gradients[((index % gradients.count) + gradients.count) % gradients.count]
        return LinearGradient(colors: [pair.top, pair.bottom], startPoint: .top, endPoint: .bottom)
    }
}
