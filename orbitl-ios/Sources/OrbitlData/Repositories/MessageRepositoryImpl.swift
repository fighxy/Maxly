import Foundation
import SwiftData
import OrbitlDomain

/// Реализация `MessageRepository` поверх SwiftData, сервера и очереди исходящих.
///
/// Пагинация идёт курсором по `timestamp`: страница содержит `pageSize` сообщений
/// строго старше курсора, от новых к старым. `loadMore` сначала берёт страницу
/// из кэша и, если её не хватает, догружает историю с сервера. Для каждого чата
/// репозиторий помнит, сколько сообщений показано (окно), и `loadOlder` расширяет
/// окно на страницу.
///
/// Отправка оптимистичная: сообщение сразу записывается со статусом `sending`
/// и ставится в `OutboxQueue`. Очередь сообщает результат через `OutboxStore`:
/// при успехе статус `sent` и `serverId`, при ошибке `failed`.
///
/// Swift 6: это `@ModelActor` со своим фоновым контекстом. Модели SwiftData
/// не покидают актор, наружу выходят доменные модели и `MessageRecord`.
@ModelActor
public actor MessageRepositoryImpl: MessageRepository, OutboxStore {
    public static let pageSize = 50

    private struct Observer {
        let chatId: String
        let continuation: AsyncStream<[Message]>.Continuation
    }

    private var observers: [UUID: Observer] = [:]
    /// Сколько последних сообщений показано в каждом чате.
    private var windows: [String: Int] = [:]
    /// Текущий автор исходящих. Задаётся после входа.
    private var currentUserId = ""
    private var api: any MaxAPI = MaxAPIClient()
    private var outbox: OutboxQueue?

    public init(modelContainer: ModelContainer, api: any MaxAPI) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
    }

    public static func make(stack: SwiftDataStack, api: any MaxAPI) -> MessageRepositoryImpl {
        MessageRepositoryImpl(modelContainer: stack.container, api: api)
    }

    /// Подключает очередь исходящих. Очередь держит репозиторий слабой ссылкой.
    public func attach(outbox: OutboxQueue) async {
        self.outbox = outbox
        await outbox.attach(store: self)
    }

    public func setCurrentUser(id: String) {
        currentUserId = id
    }

    // MARK: MessageRepository

    /// Сообщения чата от старых к новым, в пределах текущего окна.
    /// Первое значение приходит сразу из кэша.
    public nonisolated func messages(chatId: String) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, chatId: chatId, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    /// Расширяет окно на одну страницу, при необходимости догружая историю с сервера.
    public func loadOlder(chatId: String) async throws(OrbitlError) {
        let shown = windows[chatId] ?? Self.pageSize
        let window = (try? fetchPage(chatId: chatId, before: nil, limit: shown)) ?? []
        _ = try await loadMore(chatId: chatId, before: window.last?.timestamp)
        windows[chatId] = shown + Self.pageSize
        notify(chatId: chatId)
    }

    /// Оптимистичная отправка: сообщение сразу попадает в базу со статусом `sending`
    /// и ставится в очередь. Результат отправки подписчики увидят через смену статуса.
    public func send(text: String, chatId: String) async throws(OrbitlError) {
        let localId = "local-\(UUID().uuidString)"
        let message = SDMessage(
            id: localId,
            chatId: chatId,
            authorId: currentUserId,
            text: text,
            timestamp: .now,
            status: .sending
        )
        do {
            message.chat = try chat(id: chatId)
            modelContext.insert(message)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: chatId)
        await outbox?.enqueue(localId)
    }

    /// Повторная отправка сообщения со статусом `failed`.
    public func retry(messageId: String) async throws(OrbitlError) {
        guard let message = try? message(id: messageId), message.status == .failed else { return }
        do {
            message.status = .sending
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: message.chatId)
        await outbox?.enqueue(messageId)
    }

    // MARK: Страницы (курсор по timestamp)

    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    /// Сначала берётся из кэша. Если в кэше меньше `pageSize`, недостающее
    /// догружается с сервера, сохраняется и страница читается заново.
    /// Без сети возвращается то, что есть в кэше.
    public func loadMore(chatId: String, before: Date?) async throws(OrbitlError) -> [Message] {
        let local = try page(chatId: chatId, before: before)
        guard local.count < Self.pageSize else { return local.map(\.domain) }

        let cursor = local.last?.timestamp ?? before
        switch await api.fetchMessages(chatId: chatId, before: cursor, limit: Self.pageSize - local.count) {
        case .success(let records):
            guard !records.isEmpty else { return local.map(\.domain) }
            try upsert(records)
            return try page(chatId: chatId, before: before).map(\.domain)
        case .failure(.offline):
            return local.map(\.domain)
        case .failure(let error):
            if local.isEmpty { throw error.orbitlError }
            return local.map(\.domain)
        }
    }

    /// Самые свежие сообщения чата с сервера (для периодического опроса).
    public func fetchLatest(chatId: String) async throws(OrbitlError) {
        switch await api.fetchMessages(chatId: chatId, before: nil, limit: Self.pageSize) {
        case .success(let records):
            try upsert(records)
        case .failure(let error):
            throw error.orbitlError
        }
    }

    /// Страница из кэша, без обращения к серверу.
    public func page(chatId: String, before: Date?, limit: Int = pageSize) throws(OrbitlError) -> [MessageRecord] {
        do {
            return try fetchPage(chatId: chatId, before: before, limit: limit).map(Self.record)
        } catch {
            throw .storageError
        }
    }

    // MARK: Запись (вызывается из SyncEngine)

    /// Вставляет новые сообщения и обновляет существующие. Сообщение с сервера
    /// совпадает с локальным по `id` или по `serverId` (своё отправленное).
    public func upsert(_ records: [MessageRecord]) throws(OrbitlError) {
        var touched = Set<String>()
        do {
            for record in records {
                if let message = try message(id: record.id) ?? message(serverId: record.serverId ?? record.id) {
                    message.text = record.text
                    message.status = record.status
                    message.mediaId = record.mediaId
                    if let serverId = record.serverId { message.serverId = serverId }
                } else {
                    let message = SDMessage(
                        id: record.id,
                        chatId: record.chatId,
                        authorId: record.authorId,
                        text: record.text,
                        timestamp: record.timestamp,
                        status: record.status,
                        mediaId: record.mediaId,
                        serverId: record.serverId ?? record.id
                    )
                    message.chat = try chat(id: record.chatId)
                    modelContext.insert(message)
                }
                touched.insert(record.chatId)
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        touched.forEach(notify(chatId:))
    }

    public func delete(messageId: String) throws(OrbitlError) {
        do {
            guard let message = try message(id: messageId) else { return }
            let chatId = message.chatId
            modelContext.delete(message)
            try modelContext.save()
            notify(chatId: chatId)
        } catch {
            throw .storageError
        }
    }

    // MARK: OutboxStore

    public func pendingOutgoing() -> [MessageRecord] {
        let sending = MessageStatus.sending.rawValue
        let descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.statusRaw == sending },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(Self.record)
    }

    public func outgoing(localId: String) -> MessageRecord? {
        guard let message = try? message(id: localId), message.status == .sending else { return nil }
        return Self.record(message)
    }

    public func markSent(localId: String, serverId: String, timestamp: Date) {
        guard let message = try? message(id: localId) else { return }
        message.status = .sent
        message.serverId = serverId
        message.timestamp = timestamp
        try? modelContext.save()
        notify(chatId: message.chatId)
    }

    public func markFailed(localId: String) {
        guard let message = try? message(id: localId) else { return }
        message.status = .failed
        try? modelContext.save()
        notify(chatId: message.chatId)
    }

    // MARK: Внутреннее

    /// Серверный id сообщения, если оно уже отправлено.
    func serverId(of localId: String) -> String? {
        (try? message(id: localId))?.serverId
    }

    func message(id: String) throws -> SDMessage? {
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func message(serverId: String) throws -> SDMessage? {
        let optionalId: String? = serverId
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.serverId == optionalId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPage(chatId: String, before: Date?, limit: Int) throws -> [SDMessage] {
        let predicate: Predicate<SDMessage>
        if let cursor = before {
            predicate = #Predicate { $0.chatId == chatId && $0.timestamp < cursor }
        } else {
            predicate = #Predicate { $0.chatId == chatId }
        }
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func chat(id: String) throws -> SDChat? {
        var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func addObserver(_ id: UUID, chatId: String, _ continuation: AsyncStream<[Message]>.Continuation) {
        observers[id] = Observer(chatId: chatId, continuation: continuation)
        continuation.yield(snapshot(chatId: chatId))
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notify(chatId: String) {
        let targets = observers.values.filter { $0.chatId == chatId }
        guard !targets.isEmpty else { return }
        let messages = snapshot(chatId: chatId)
        for observer in targets {
            observer.continuation.yield(messages)
        }
    }

    /// Последние `windows[chatId]` сообщений, от старых к новым.
    private func snapshot(chatId: String) -> [Message] {
        let limit = windows[chatId] ?? Self.pageSize
        let newestFirst = (try? fetchPage(chatId: chatId, before: nil, limit: limit)) ?? []
        return newestFirst.reversed().map { Self.record($0).domain }
    }

    private static func record(_ message: SDMessage) -> MessageRecord {
        MessageRecord(
            id: message.id,
            serverId: message.serverId,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: message.timestamp,
            status: message.status,
            mediaId: message.mediaId
        )
    }
}
