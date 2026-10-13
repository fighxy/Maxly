import Foundation
import MaxlyDomain

/// Скрытая вкладка «Все» в `UserDefaults`: одна настройка на устройство.
@MainActor
public final class UserDefaultsFolderDisplayStore: FolderDisplayStore {
    public static let hideAllKey = "maxly.folders.hideAllChats"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hidesAllChats: Bool {
        get { defaults.bool(forKey: Self.hideAllKey) }
        set { defaults.set(newValue, forKey: Self.hideAllKey) }
    }
}
