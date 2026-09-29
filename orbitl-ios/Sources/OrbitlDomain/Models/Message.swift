import Foundation

/// Доменная модель `Message`. Чистый Swift, без SwiftData и типов Kotlin.
// TODO: поля по модели ядра max-kmp-core (architecture.md, «Слои»).
public struct Message: Identifiable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
