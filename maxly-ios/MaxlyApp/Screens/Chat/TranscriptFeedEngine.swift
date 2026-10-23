import Foundation

/// Какой движок рисует ленту чата.
///
/// `.collection` — UICollectionView, старое сверху, новое снизу.
/// `.lazyStack` — прежний SwiftUI ScrollView/LazyVStack (запасной путь).
enum TranscriptFeedEngine {
    enum Kind: String, Sendable {
        case collection
        case lazyStack
    }

    /// Ключ UserDefaults. Значения: `collection` | `lazyStack`.
    /// По умолчанию — collection. Откат на устройстве:
    /// `UserDefaults.standard.set("lazyStack", forKey: TranscriptFeedEngine.defaultsKey)`.
    static let defaultsKey = "maxly.transcript.feed"

    static var kind: Kind {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let kind = Kind(rawValue: raw) {
            return kind
        }
        return .collection
    }
}
