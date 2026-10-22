import Foundation

/// Какой движок рисует ленту чата.
///
/// `.collection` — UICollectionView + recycling (цель «как Telegram»).
/// `.lazyStack` — прежний SwiftUI ScrollView/LazyVStack (запасной путь).
enum TranscriptFeedEngine {
    enum Kind: String, Sendable {
        case collection
        case lazyStack
    }

    /// Ключ UserDefaults. Значения: `collection` | `lazyStack`.
    /// По умолчанию — lazyStack (B/C/D уже активны). Включить UICollectionView после
    /// проверки на устройстве:
    /// `UserDefaults.standard.set("collection", forKey: TranscriptFeedEngine.defaultsKey)`.
    static let defaultsKey = "maxly.transcript.feed"

    static var kind: Kind {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let kind = Kind(rawValue: raw) {
            return kind
        }
        return .lazyStack
    }
}
