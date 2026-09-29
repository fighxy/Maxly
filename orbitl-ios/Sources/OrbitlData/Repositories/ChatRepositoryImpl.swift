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
    private var api: any MaxAPI = MaxAPIClient()

    public init(modelContainer: ModelContainer, api: any MaxAPI) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
    }

    public static func make(stack: SwiftDataStack, api: any MaxAPI) -> ChatRepositoryImpl {
        ChatRepositoryImpl(modelContainer: stack.container, api: api)
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
        switch await api.fetchChats() {
        case .success(let records):
            try upsert(records)
        case .failure(let error):
            throw error.orbitlError
        }
    }

    /// Обновление одного чата: запрашивает список и обновляет только этот чат.
    // TODO: заменить на точечный запрос чата, когда он появится в MaxAPI.
    public func refresh(chatId: String) async throws(OrbitlError) {
        switch await api.fetchChats() {
        case .success(let records):
            try upsert(records.filter { $0.id == chatId })
        case .failure(let error):
            throw error.orbitlError
        }
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
                    chat.type = record.type
                    chat.lastMessageId = record.lastMessageId
                    chat.unreadCount = record.unreadCount
                    chat.updatedAt = record.updatedAt
                } else {
                    modelContext.insert(SDChat(
                        id: record.id,
                        title: record.title,
                        type: record.type,
                        lastMessageId: record.lastMessageId,
                        unreadCount: record.unreadCount,
                        updatedAt: record.updatedAt
                    ))
                }
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Удаляет чат вместе с сообщениями (каскадное удаление).
    public func delete(chatId: String) throws(OrbitlError) {
        do {
            try modelContext.delete(model: SDChat.self, where: #Predicate { $0.id == chatId })
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Сбрасывает счётчик непрочитанных локально и отправляет отметку на сервер.
    /// Если сервер ответил ошибкой, локальное изменение остаётся, а ошибка пробрасывается.
    public func markAsRead(chatId: String) async throws(OrbitlError) {
        try markReadLocally(chatId: chatId)
        if case .failure(let error) = await api.markRead(chatId: chatId) {
            throw error.orbitlError
        }
    }

    private func markReadLocally(chatId: String) throws(OrbitlError) {
        do {
            var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == chatId })
            descriptor.fetchLimit = 1
            guard let chat = try modelContext.fetch(descriptor).first else { return }
            chat.unreadCount = 0
            try modelContext.save()
        } catch {
            throw .storageError
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
        return chats.map(Self.domain)
    }

    private static func domain(_ chat: SDChat) -> Chat {
        Chat(
            id: chat.id,
            title: chat.title,
            type: chat.type,
            lastMessageId: chat.lastMessageId,
            unreadCount: chat.unreadCount,
            updatedAt: chat.updatedAt
        )
    }
}
