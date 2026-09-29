import Foundation
import SwiftData
import OrbitlDomain

/// Реализация `MessageRepository` поверх SwiftData.
///
/// Пагинация идёт курсором по `timestamp`: страница содержит `pageSize` сообщений
/// строго старше курсора, отсортированных от новых к старым. Для каждого чата
/// репозиторий помнит, сколько сообщений сейчас показано (окно), и `loadOlder`
/// расширяет окно на страницу.
///
/// Swift 6: как и `ChatRepositoryImpl`, это `@ModelActor` со своим фоновым контекстом.
@ModelActor
public actor MessageRepositoryImpl: MessageRepository {
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

    public static func make(stack: SwiftDataStack) -> MessageRepositoryImpl {
        MessageRepositoryImpl(modelContainer: stack.container)
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

    /// Расширяет окно на одну страницу. Если в кэше старше ничего нет, догружает с сервера.
    public func loadOlder(chatId: String) async throws(OrbitlError) {
        let shown = windows[chatId] ?? Self.pageSize
        let cached = (try? count(chatId: chatId)) ?? 0
        if cached <= shown {
            // TODO: запросить историю старше самого старого сообщения
            // (oldestTimestamp(chatId:)) через MaxAPIClient и передать в upsert(_:).
        }
        windows[chatId] = shown + Self.pageSize
        notify(chatId: chatId)
    }

    /// Оптимистичная отправка: сообщение сразу попадает в базу со статусом `sending`.
    public func send(text: String, chatId: String) async throws(OrbitlError) {
        let message = SDMessage(
            id: "local-\(UUID().uuidString)",
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
            throw .unknown
        }
        notify(chatId: chatId)
        // TODO: поставить в OutboxQueue. После ответа сервера заменить локальный id
        // на серверный и сменить статус на sent, при ошибке на failed.
    }

    // MARK: Страницы (курсор по timestamp)

    /// Страница сообщений строго старше `before` (или самых новых, если `before == nil`),
    /// от новых к старым.
    public func page(chatId: String, before: Date?, limit: Int = pageSize) throws(OrbitlError) -> [MessageRecord] {
        do {
            return try fetchPage(chatId: chatId, before: before, limit: limit).map(Self.record)
        } catch {
            throw .unknown
        }
    }

    /// Самое старое сообщение в кэше, курсор для запроса истории с сервера.
    public func oldestTimestamp(chatId: String) -> Date? {
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.chatId == chatId },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.timestamp
    }

    // MARK: Запись (вызывается из SyncEngine и OutboxQueue)

    /// Вставляет новые сообщения и обновляет существующие по id.
    public func upsert(_ records: [MessageRecord]) throws(OrbitlError) {
        var touched = Set<String>()
        do {
            for record in records {
                let id = record.id
                var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let message = try modelContext.fetch(descriptor).first {
                    message.text = record.text
                    message.status = record.status
                    message.mediaId = record.mediaId
                } else {
                    let message = SDMessage(
                        id: record.id,
                        chatId: record.chatId,
                        authorId: record.authorId,
                        text: record.text,
                        timestamp: record.timestamp,
                        status: record.status,
                        mediaId: record.mediaId
                    )
                    message.chat = try chat(id: record.chatId)
                    modelContext.insert(message)
                }
                touched.insert(record.chatId)
            }
            try modelContext.save()
        } catch {
            throw .unknown
        }
        touched.forEach(notify(chatId:))
    }

    /// Меняет статус сообщения, например после ответа сервера или ошибки отправки.
    public func updateStatus(messageId: String, to status: MessageStatus) throws(OrbitlError) {
        do {
            var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == messageId })
            descriptor.fetchLimit = 1
            guard let message = try modelContext.fetch(descriptor).first else { return }
            message.status = status
            try modelContext.save()
            notify(chatId: message.chatId)
        } catch {
            throw .unknown
        }
    }

    public func delete(messageId: String) throws(OrbitlError) {
        do {
            var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == messageId })
            descriptor.fetchLimit = 1
            guard let message = try modelContext.fetch(descriptor).first else { return }
            let chatId = message.chatId
            modelContext.delete(message)
            try modelContext.save()
            notify(chatId: chatId)
        } catch {
            throw .unknown
        }
    }

    // MARK: Внутреннее

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

    private func count(chatId: String) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<SDMessage>(predicate: #Predicate { $0.chatId == chatId }))
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
        // TODO: когда в доменной модели Message появятся поля, переносить их сюда.
        return newestFirst.reversed().map { Message(id: $0.id) }
    }

    private static func record(_ message: SDMessage) -> MessageRecord {
        MessageRecord(
            id: message.id,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: message.timestamp,
            status: message.status,
            mediaId: message.mediaId
        )
    }
}
