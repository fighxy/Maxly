import SwiftUI

public extension Color {
    /// Синий акцент действий и контрастный текст на его заливке.
    static let maxlyAccent = adaptive(light: 0x0070E0, dark: 0x64B5F6)
    static let maxlyOnAccent = adaptive(light: 0xFFFFFF, dark: 0x102030)

    /// Поверхности чата: серо-голубой фон ленты, белые входящие (в тёмной теме — тёмные) и
    /// исходящие фирменного индиго с белым текстом в обеих темах. Оттенок один на день и ночь:
    /// свой пузырь узнаётся по цвету. Текст и контролы на заливке имеют свои токены; белый текст
    /// на заливке — не ниже 5:1, время и вторичный текст — около 3.5:1.
    static let maxlyChatBackground = adaptive(light: 0xE9EEF2, dark: 0x101A24)
    static let maxlyOutgoing = adaptive(light: 0x4B59E6, dark: 0x3A43A6)
    static let maxlyOutgoingText = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let maxlyOutgoingSecondary = adaptive(light: 0xD7DAF9, dark: 0xCED0E9)
    static let maxlyOutgoingAccent = adaptive(light: 0xFFFFFF, dark: 0xDDE1FF)
    static let maxlyOnOutgoingAccent = adaptive(light: 0x3A47D6, dark: 0x2C3590)
    /// Две галочки «прочитано» в списке чатов — голубые. На исходящем пузыре они цвета его
    /// текста (`maxlyOutgoingText`): голубое на индиго не читается. Одна галочка «отправлено»
    /// остаётся цвета времени.
    static let maxlyReadMark = adaptive(light: 0x1E9AE8, dark: 0x7ACBFF)
    /// Синий круг «Избранного» и архива.
    static let maxlySpecialAvatar = Color(red: 0.30, green: 0.62, blue: 0.98)
    static let maxlyOnline = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// Серый бейдж чата без звука.
    static let maxlyMutedBadge = Color.gray.opacity(0.55)
    #if os(iOS)
    /// Тёмный входящий заметно светлее фона ленты, плюс тонкая кромка в `MessageBubble`.
    static let maxlyIncoming = adaptive(light: 0xFFFFFF, dark: 0x1F2B38)
    static let maxlyIncomingOnWallpaper = maxlyIncoming
    /// Подложка плоского поля поиска.
    static let maxlyField = Color(uiColor: .tertiarySystemFill)
    /// Чуть серый фон закреплённых строк.
    static let maxlyPinnedBackground = Color(uiColor: .secondarySystemBackground)
    static let maxlyBackground = Color(uiColor: .systemBackground)
    #else
    static let maxlyIncoming = adaptive(light: 0xFFFFFF, dark: 0x1F2B38)
    static let maxlyIncomingOnWallpaper = maxlyIncoming
    static let maxlyField = Color.gray.opacity(0.12)
    static let maxlyPinnedBackground = Color.gray.opacity(0.08)
    static let maxlyBackground = Color.white
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
