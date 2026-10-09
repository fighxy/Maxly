import Foundation
import MaxlyDomain

/// Недавние чаты из поиска в `UserDefaults`. Это не переписка, поэтому база для них не нужна;
/// выход из аккаунта стирает их вместе с остальными данными (`clear`).
public actor RecentSearchesStore: RecentSearchStore {
    public static let limit = 20

    private let suiteName: String?
    private let key: String

    /// `suiteName == nil` — стандартные настройки приложения. Тесты передают свой набор.
    public init(suiteName: String? = nil, key: String = "maxly.recentSearches") {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func recent() async -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public func add(chatId: String) async {
        var ids = await recent()
        ids.removeAll { $0 == chatId }
        ids.insert(chatId, at: 0)
        defaults.set(Array(ids.prefix(Self.limit)), forKey: key)
    }

    public func remove(chatId: String) async {
        var ids = await recent()
        ids.removeAll { $0 == chatId }
        defaults.set(ids, forKey: key)
    }

    public func clear() async {
        defaults.removeObject(forKey: key)
    }
}
