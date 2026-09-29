import Foundation
import SwiftData
import OrbitlDomain

/// Реализация `ChatRepository` поверх SwiftData.
///
/// Swift 6: модели SwiftData не Sendable, поэтому репозиторий сделан как
/// `@ModelActor`. У него свой фоновый `ModelContext`, и все записи идут вне
/// главного актора. Наружу выходят только доменные модели и Sendable-записи.
@ModelActor
public actor ChatRepositoryImpl: ChatRepository {
    private var observers: [UUID: AsyncStream<[Chat]>.Continuation] = [:]

    public static func make(stack: SwiftDataStack) -> ChatRepositoryImpl {
        ChatRepositoryImpl(modelContainer: stack.container)
    }

    // MARK: ChatRepository

    /// Список чатов, отсортированный по последней активности.
    /// Первое значение приходит сразу из кэша, следующие после каждой записи.
    public nonisolated func chats() -> AsyncStream<[Chat]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    /// Обновление с сервера. Кэш уже показан, здесь только фоновая догрузка.
    public func refresh() async throws(OrbitlError) {
        // TODO: запросить список чатов через MaxAPIClient или SyncEngine
        // и передать результат в upsert(_:). Ошибки MaxError перевести в OrbitlError.
    }

    // MARK: Запись (вызывается из SyncEngine)

    /// Вставляет новые чаты и обновляет существующие по id.
    public func upsert(_ records: [ChatRecord]) throws(OrbitlError) {
        do {
            for record in records {
                let id = record.id
                var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let chat = try modelContext.fetch(descriptor).first {
                    chat.title = record.title
                    chat.kind = record.kind
                    chat.lastMessageId = record.lastMessageId
                    chat.unreadCount = record.unreadCount
                    chat.updatedAt = record.updatedAt
                } else {
                    modelContext.insert(SDChat(
                        id: record.id,
                        title: record.title,
                        kind: record.kind,
                        lastMessageId: record.lastMessageId,
                        unreadCount: record.unreadCount,
                        updatedAt: record.updatedAt
                    ))
                }
            }
            try modelContext.save()
        } catch {
            throw .unknown
        }
        notify()
    }

    /// Удаляет чат вместе с сообщениями (каскадное удаление).
    public func delete(chatId: String) throws(OrbitlError) {
        do {
            try modelContext.delete(model: SDChat.self, where: #Predicate { $0.id == chatId })
            try modelContext.save()
        } catch {
            throw .unknown
        }
        notify()
    }

    /// Сбрасывает счётчик непрочитанных.
    public func markRead(chatId: String) throws(OrbitlError) {
        do {
            var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == chatId })
            descriptor.fetchLimit = 1
            guard let chat = try modelContext.fetch(descriptor).first else { return }
            chat.unreadCount = 0
            try modelContext.save()
        } catch {
            throw .unknown
        }
        notify()
    }

    // MARK: Наблюдатели

    private func addObserver(_ id: UUID, _ continuation: AsyncStream<[Chat]>.Continuation) {
        observers[id] = continuation
        continuation.yield(snapshot())
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notify() {
        guard !observers.isEmpty else { return }
        let chats = snapshot()
        for continuation in observers.values {
            continuation.yield(chats)
        }
    }

    private func snapshot() -> [Chat] {
        let descriptor = FetchDescriptor<SDChat>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let chats = (try? modelContext.fetch(descriptor)) ?? []
        // TODO: когда в доменной модели Chat появятся поля, переносить их сюда.
        return chats.map { Chat(id: $0.id) }
    }
}
