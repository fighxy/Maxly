import Foundation
import OrbitleDomain

/// Настройки приватного режима в `UserDefaults`: одни на устройство, выход из аккаунта
/// и вход в другой их не трогают. Незнакомый стиль читается как заглушки.
@MainActor
public final class UserDefaultsPrivateModeStore: PrivateModeStore {
    public static let enabledKey = "maxly.privateMode.enabled"
    public static let styleKey = "maxly.privateMode.style"
    public static let quickToggleKey = "maxly.privateMode.quickToggle"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PrivateModePreferences {
        let style = defaults.string(forKey: Self.styleKey).flatMap(PrivateModeStyle.init(rawValue:))
        // Кнопка по умолчанию видна: ключа нет — значит, её не выключали.
        let quick = defaults.object(forKey: Self.quickToggleKey) == nil ? true : defaults.bool(forKey: Self.quickToggleKey)
        return PrivateModePreferences(
            isEnabled: defaults.bool(forKey: Self.enabledKey),
            style: style ?? .placeholder,
            showsQuickToggle: quick
        )
    }

    public func save(_ preferences: PrivateModePreferences) {
        defaults.set(preferences.isEnabled, forKey: Self.enabledKey)
        defaults.set(preferences.style.rawValue, forKey: Self.styleKey)
        defaults.set(preferences.showsQuickToggle, forKey: Self.quickToggleKey)
    }
}
