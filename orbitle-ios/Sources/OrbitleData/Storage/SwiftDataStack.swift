import Foundation
import ObjectiveC
import SwiftData

/// Ошибки слоя хранения.
public enum StorageError: Error {
    /// Не удалось создать или открыть хранилище SwiftData (например, сломана миграция).
    case containerCreationFailed(underlying: any Error)
    /// Не удалось записать изменения.
    case writeFailed(underlying: any Error)
}

/// Контейнер SwiftData для всего клиента.
///
/// Один экземпляр на приложение, создаётся в `AppContainer`. Чтение и запись идут
/// через репозитории с `ModelActor`, у каждого из которых свой фоновый контекст.
public final class SwiftDataStack: Sendable {
    /// Все модели локальной базы. Новую модель нужно добавить сюда.
    static func makeSchema() -> Schema {
        Schema([
            SDChat.self,
            SDMessage.self,
            SDUser.self,
            SDMediaItem.self,
        ])
    }

    public let container: ModelContainer

    private static let creationLock = NSLock()

    /// - Parameter inMemory: `true` для тестов и превью, данные не пишутся на диск.
    public init(inMemory: Bool = false) throws(StorageError) {
        BundleNameFallback.installIfNeeded()
        // Контейнеры создаются по одному. SwiftData строит модель схемы из метаданных `@Model`
        // не потокобезопасно, и параллельные тесты, каждый со своим контейнером, роняли
        // процесс с signal 11. В приложении контейнер один, лишней задержки нет.
        Self.creationLock.lock()
        defer { Self.creationLock.unlock() }
        let schema = Self.makeSchema()
        do {
            if inMemory {
                // Своё имя у каждой базы в памяти: хранилища разных контейнеров не пересекаются.
                let configuration = ModelConfiguration(
                    "Maxly-\(UUID().uuidString)",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: [configuration])
            } else {
                let support = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let directory = support.appending(path: "Maxly", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                #if os(iOS)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: directory.path
                )
                #endif
                let storeURL = directory.appending(path: "Maxly.store")
                let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, configurations: [configuration])
            }
        } catch let error as StorageError {
            throw error
        } catch {
            throw .containerCreationFailed(underlying: error)
        }
    }

    /// `swift test` собирает бинарник без `CFBundleName`, и SwiftData из-за этого
    /// вызывает fatalError. В приложении имя уже есть в Info.plist, подмена не нужна.
    private enum BundleNameFallback {
        private static let once: Void = {
            let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            guard name?.isEmpty != false else { return }
            guard
                let original = class_getInstanceMethod(Bundle.self, #selector(Bundle.object(forInfoDictionaryKey:))),
                let replacement = class_getInstanceMethod(Bundle.self, #selector(Bundle.orbitle_object(forInfoDictionaryKey:)))
            else { return }
            method_exchangeImplementations(original, replacement)
        }()

        static func installIfNeeded() {
            _ = once
        }
    }

    /// Пользователи и медиа-записи. Чаты и сообщения стирают свои репозитории, своим контекстом,
    /// иначе их `ModelActor` остались бы со старыми объектами.
    public func eraseUsersAndMedia() throws(StorageError) {
        let context = ModelContext(container)
        do {
            try context.delete(model: SDUser.self)
            try context.delete(model: SDMediaItem.self)
            try context.save()
        } catch {
            throw .writeFailed(underlying: error)
        }
    }
}

extension ModelContext {
    /// Пакетный `delete(model:where:)` падает, если у сообщения есть связь с чатом:
    /// Core Data не обнуляет обратную связь и сохранение отвечает ошибкой хранилища.
    /// По одному связь снимается обычным правилом.
    func deleteInstances<T: PersistentModel>(model _: T.Type, where predicate: Predicate<T>? = nil) throws {
        for object in try fetch(FetchDescriptor<T>(predicate: predicate)) {
            delete(object)
        }
    }
}

private extension Bundle {
    @objc func orbitle_object(forInfoDictionaryKey key: String) -> Any? {
        let value = orbitle_object(forInfoDictionaryKey: key)
        guard self === Bundle.main else { return value }
        if key == "CFBundleName", (value as? String)?.isEmpty != false {
            return "Maxly"
        }
        if key == "CFBundleIdentifier", (value as? String)?.isEmpty != false {
            return "app.maxly.ios"
        }
        return value
    }
}
