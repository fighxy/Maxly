import Foundation
import SwiftData

/// Ошибки слоя хранения.
public enum StorageError: Error {
    /// Не удалось создать или открыть хранилище SwiftData (например, сломана миграция).
    case containerCreationFailed(underlying: any Error)
}

/// Контейнер SwiftData для всего клиента.
///
/// Один экземпляр на приложение, создаётся в `AppContainer`. Главный контекст
/// нужен только для чтения на главном акторе. Все записи идут через репозитории
/// с `@ModelActor`, у каждого из которых свой фоновый контекст.
public final class SwiftDataStack: Sendable {
    /// Все модели локальной базы. Новую модель нужно добавить сюда.
    static var schema: Schema {
        Schema([
            SDChat.self,
            SDMessage.self,
            SDUser.self,
            SDMediaItem.self,
        ])
    }

    public let container: ModelContainer

    /// - Parameter inMemory: `true` для тестов и превью, данные не пишутся на диск.
    public init(inMemory: Bool = false) throws(StorageError) {
        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory
            // TODO: architecture.md, «Безопасность». Файл хранилища должен лежать
            // под Data Protection (completeUnlessOpen или complete).
        )
        do {
            container = try ModelContainer(for: Self.schema, configurations: [configuration])
        } catch {
            throw .containerCreationFailed(underlying: error)
        }
    }

    /// Контекст главного актора для чтения из UI-слоя (например, превью).
    @MainActor
    public var mainContext: ModelContext {
        container.mainContext
    }

    /// Новый контекст для разовой работы вне главного актора.
    /// Для постоянной фоновой работы используйте репозитории с `@ModelActor`.
    public func makeContext() -> ModelContext {
        ModelContext(container)
    }

    /// Полная очистка базы при выходе из аккаунта (architecture.md, «Аутентификация и сессии»).
    public func eraseAll() throws(StorageError) {
        let context = makeContext()
        do {
            try context.delete(model: SDMessage.self)
            try context.delete(model: SDChat.self)
            try context.delete(model: SDUser.self)
            try context.delete(model: SDMediaItem.self)
            try context.save()
        } catch {
            throw .containerCreationFailed(underlying: error)
        }
    }
}
