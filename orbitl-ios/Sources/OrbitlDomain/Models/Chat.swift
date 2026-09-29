import Foundation

/// Доменная модель `Chat`. Чистый Swift, без SwiftData и типов Kotlin.
// TODO: поля по модели ядра max-kmp-core (architecture.md, «Слои»).
public struct Chat: Identifiable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
