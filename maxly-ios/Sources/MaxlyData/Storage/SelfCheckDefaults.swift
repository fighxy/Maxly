import Foundation
import MaxlyDomain

/// «Показывать мой онлайн» в `UserDefaults`. По умолчанию включено.
public final class UserDefaultsSelfCheckStore: SelfCheckStore, @unchecked Sendable {
    public static let key = "maxly.settings.showsOwnPresence"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func showsOwnPresence() -> Bool {
        defaults.object(forKey: Self.key) == nil ? true : defaults.bool(forKey: Self.key)
    }

    public func setShowsOwnPresence(_ shows: Bool) {
        defaults.set(shows, forKey: Self.key)
    }
}

/// Разовая чистка после перехода режима призрака на ядро: до него флаги и выбор приватности
/// лежали в `UserDefaults` под `orbitle.ghost.*` и `orbitle.privacy.local.*`. Теперь они в ядре
/// и на сервере, старые ключи только сбивали бы с толку. «Показывать мой онлайн» переезжает на
/// новый ключ и остаётся.
public enum GhostDefaultsMigration {
    public static let doneKey = "maxly.migrations.ghostCore"
    static let legacyPrefixes = ["orbitle.ghost.", "orbitle.privacy.local."]
    static let legacySelfCheckKey = "orbitle.ghost.showsOwnPresence"

    /// Один раз на установку; повторный вызов ничего не делает.
    public static func run(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        if defaults.object(forKey: UserDefaultsSelfCheckStore.key) == nil,
           defaults.object(forKey: legacySelfCheckKey) != nil {
            defaults.set(defaults.bool(forKey: legacySelfCheckKey), forKey: UserDefaultsSelfCheckStore.key)
        }
        let stale = defaults.dictionaryRepresentation().keys.filter { key in
            legacyPrefixes.contains { key.hasPrefix($0) }
        }
        for key in stale { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: doneKey)
        if !stale.isEmpty { Log.info(.settings, "Старые ключи режима призрака убраны: \(stale.count)") }
    }
}
