import Foundation
import MaxlyDomain

/// Настройки оформления в `UserDefaults`: одни на устройство, выход из аккаунта их не трогает.
///
/// Шаг, тема, обои и шрифт хранятся именами (`large`, `dark`, `autumnAuto`, `inter`), толщина — числом, незнакомое имя читается как значение
/// по умолчанию.
@MainActor
public final class UserDefaultsAppearanceStore: AppearanceStore {
    public static let textSizeKey = "maxly.appearance.textSize"
    public static let themeKey = "maxly.appearance.theme"
    public static let wallpaperKey = "maxly.appearance.wallpaper"
    public static let fontKey = "maxly.appearance.font"
    public static let fontWeightKey = "maxly.appearance.fontWeight"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppearancePreferences {
        let size = defaults.string(forKey: Self.textSizeKey).flatMap(TextSizeStep.init(rawValue:))
        let theme = defaults.string(forKey: Self.themeKey).flatMap(ThemeMode.init(rawValue:))
        let wallpaper = defaults.string(forKey: Self.wallpaperKey).flatMap(ChatWallpaper.init(rawValue:))
        let font = defaults.string(forKey: Self.fontKey).flatMap(AppFont.init(rawValue:))
        let weight = defaults.object(forKey: Self.fontWeightKey) as? Int
        return AppearancePreferences(
            textSize: size ?? .standard,
            theme: theme ?? .system,
            wallpaper: wallpaper ?? .standard,
            font: font ?? .system,
            fontWeight: weight ?? FontWeightScale.standard
        )
    }

    public func save(_ preferences: AppearancePreferences) {
        defaults.set(preferences.textSize.rawValue, forKey: Self.textSizeKey)
        defaults.set(preferences.theme.rawValue, forKey: Self.themeKey)
        defaults.set(preferences.wallpaper.rawValue, forKey: Self.wallpaperKey)
        defaults.set(preferences.font.rawValue, forKey: Self.fontKey)
        defaults.set(preferences.fontWeight, forKey: Self.fontWeightKey)
    }
}
