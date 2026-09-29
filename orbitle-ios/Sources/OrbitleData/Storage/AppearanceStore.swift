import Foundation
import OrbitleDomain

/// Настройки оформления в `UserDefaults`: одни на устройство, выход из аккаунта их не трогает.
///
/// Шаг и тема хранятся именами (`large`, `dark`), незнакомое имя читается как значение
/// по умолчанию.
@MainActor
public final class UserDefaultsAppearanceStore: AppearanceStore {
    public static let textSizeKey = "orbitle.appearance.textSize"
    public static let themeKey = "orbitle.appearance.theme"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppearancePreferences {
        let size = defaults.string(forKey: Self.textSizeKey).flatMap(TextSizeStep.init(rawValue:))
        let theme = defaults.string(forKey: Self.themeKey).flatMap(ThemeMode.init(rawValue:))
        return AppearancePreferences(textSize: size ?? .standard, theme: theme ?? .system)
    }

    public func save(_ preferences: AppearancePreferences) {
        defaults.set(preferences.textSize.rawValue, forKey: Self.textSizeKey)
        defaults.set(preferences.theme.rawValue, forKey: Self.themeKey)
    }
}
