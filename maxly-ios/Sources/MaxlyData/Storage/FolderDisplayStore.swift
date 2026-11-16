import Foundation
import MaxlyDomain

/// Скрытая вкладка «Все» в `UserDefaults`: одна настройка на устройство.
@MainActor
public final class UserDefaultsFolderDisplayStore: FolderDisplayStore {
    public static let hideAllKey = "maxly.folders.hideAllChats"
    /// Последние папки сервера — свои у каждого аккаунта.
    public static func lastFoldersKey(account: String) -> String { "maxly.folders.last.\(account)" }

    private let defaults: UserDefaults
    private let account: String

    public init(defaults: UserDefaults = .standard, account: String = "") {
        self.defaults = defaults
        self.account = account
    }

    public var hidesAllChats: Bool {
        get { defaults.bool(forKey: Self.hideAllKey) }
        set { defaults.set(newValue, forKey: Self.hideAllKey) }
    }

    public var lastFolders: [ChatFolder]? {
        get {
            guard !account.isEmpty, let data = defaults.data(forKey: Self.lastFoldersKey(account: account)) else { return nil }
            return try? JSONDecoder().decode([ChatFolder].self, from: data)
        }
        set {
            guard !account.isEmpty else { return }
            let key = Self.lastFoldersKey(account: account)
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
