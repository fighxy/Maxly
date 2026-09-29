import Foundation
import OrbitlDomain

/// Отметки журнала звонков в `UserDefaults`, отдельно для каждого аккаунта: время последнего
/// просмотра вкладки «Звонки» и звонки, скрытые на устройстве.
@MainActor
public final class UserDefaultsCallHistoryMarks: CallHistoryMarks {
    private let defaults: UserDefaults
    private let seenKey: String
    private let hiddenKey: String

    public init(userId: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seenKey = Self.seenKey(userId)
        hiddenKey = Self.hiddenKey(userId)
    }

    public var lastSeen: Date? {
        get {
            guard defaults.object(forKey: seenKey) != nil else { return nil }
            return Date(timeIntervalSince1970: defaults.double(forKey: seenKey))
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: seenKey)
            } else {
                defaults.removeObject(forKey: seenKey)
            }
        }
    }

    public var hiddenIds: Set<String> {
        get { Set(defaults.stringArray(forKey: hiddenKey) ?? []) }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: hiddenKey)
            } else {
                defaults.set(newValue.sorted(), forKey: hiddenKey)
            }
        }
    }

    /// Выход из аккаунта: его отметки больше не нужны.
    public static func erase(userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: seenKey(userId))
        defaults.removeObject(forKey: hiddenKey(userId))
    }

    private static func seenKey(_ userId: String) -> String { "orbitl.calls.\(userId).lastSeen" }
    private static func hiddenKey(_ userId: String) -> String { "orbitl.calls.\(userId).hidden" }
}
