import Foundation
import MaxlyDomain

/// Отметка о новом сеансе в `UserDefaults`: как и когда вошли и показана ли панель.
///
/// Панель всплывёт и после перезапуска, если приложение закрыли раньше, чем открылся главный экран.
/// Незнакомый способ входа читается как отсутствие отметки.
@MainActor
public final class UserDefaultsAccountLimitsStore: AccountLimitsStore {
    public static let entryKey = "maxly.accountLimits.entry"
    public static let grantedAtKey = "maxly.accountLimits.grantedAt"
    public static let shownKey = "maxly.accountLimits.shown"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AccountLimits? {
        guard
            let entry = defaults.string(forKey: Self.entryKey).flatMap(AccountLimits.Entry.init(rawValue:)),
            defaults.object(forKey: Self.grantedAtKey) != nil
        else { return nil }
        return AccountLimits(
            entry: entry,
            grantedAt: Date(timeIntervalSince1970: defaults.double(forKey: Self.grantedAtKey)),
            isShown: defaults.bool(forKey: Self.shownKey)
        )
    }

    public func save(_ limits: AccountLimits?) {
        guard let limits else {
            defaults.removeObject(forKey: Self.entryKey)
            defaults.removeObject(forKey: Self.grantedAtKey)
            defaults.removeObject(forKey: Self.shownKey)
            return
        }
        defaults.set(limits.entry.rawValue, forKey: Self.entryKey)
        defaults.set(limits.grantedAt.timeIntervalSince1970, forKey: Self.grantedAtKey)
        defaults.set(limits.isShown, forKey: Self.shownKey)
    }
}
