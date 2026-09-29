import Foundation
import SwiftData
import OrbitlDomain

/// Реализация `ChatRepository` поверх SwiftData.
///
/// Swift 6: модели SwiftData не Sendable, поэтому репозиторий — `ModelActor`
/// со своим фоновым `ModelContext`. Макрос `@ModelActor` всегда добавляет
/// `init(modelContainer:)` и не видит `api`, поэтому соответствие написано вручную.
/// Наружу выходят только доменные модели и Sendable-записи.
public actor ChatRepositoryImpl: ChatRepository, ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private var observers: [UUID: AsyncStream<[Chat]>.Continuation] = [:]
    private let api: any MaxAPI
    /// Растёт при каждой очистке базы. Ответ сервера на запрос, начатый до очистки
    /// (например, до выхода), в базу уже не пишется.
    private var generation = 0

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
        let started = generation
        switch await api.fetchChats() {
        case .success(let records):
            try ensureCurrent(started)
            try upsert(records)
        case .failure(let error):
            throw error.orbitlError
        }
    }

    /// Один чат с сервера (`CHAT_INFO`).
    public func refresh(chatId: String) async throws(OrbitlError) {
        let started = generation
        switch await api.fetchChat(id: chatId) {
        case .success(let record):
            try ensureCurrent(started)
            try upsert([record])
        case .failure(let error):
            throw error.orbitlError
        }
    }

    // MARK: Запись (вызывается из SyncEngine)

    /// Вставляет новые чаты и обновляет существующие по id.
    ///
    /// Пуш чата бывает неполным, а ответ списка может быть старше уже записанного пуша,
    /// поэтому существующая строка сливается по правилам:
    /// - пустой заголовок не затирает известный;
    /// - запись старше строки (`updatedAt` меньше) не трогает превью, последнее сообщение,
    ///   время и счётчик, чтобы список не откатывался назад;
    /// - пустые `lastMessageId` и `preview` оставляют прежние значения;
    /// - отрицательный счётчик считается нулём.
    public func upsert(_ records: [ChatRecord]) throws(OrbitlError) {
        do {
            // Одна выборка на весь пакет, а не по запросу на каждую запись.
            var existing = try chats(ids: records.map(\.id))
            for record in records {
                if let chat = existing[record.id] {
                    Self.merge(record, into: chat)
                } else {
                    let chat = SDChat(
                        id: record.id,
                        title: record.title,
                        type: record.type,
                        lastMessageId: record.lastMessageId,
                        unreadCount: max(record.unreadCount, 0),
                        updatedAt: record.updatedAt,
                        preview: record.preview
                    )
                    modelContext.insert(chat)
                    existing[record.id] = chat
                }
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Правила слияния записи с уже известной строкой (см. `upsert`).
    private static func merge(_ record: ChatRecord, into chat: SDChat) {
        if !record.title.isEmpty { chat.title = record.title }
        chat.type = record.type
        guard record.updatedAt >= chat.updatedAt else { return }
        if let lastMessageId = record.lastMessageId { chat.lastMessageId = lastMessageId }
        if let preview = record.preview { chat.preview = preview }
        chat.updatedAt = record.updatedAt
        chat.unreadCount = max(record.unreadCount, 0)
    }

    /// Удаляет чат вместе с сообщениями. Сообщения без связи с чатом (записанные раньше
    /// самого чата) каскад не видит, поэтому они удаляются по `chatId` явно.
    public func delete(chatId: String) throws(OrbitlError) {
        do {
            let id = chatId
            try modelContext.delete(model: SDMessage.self, where: #Predicate { $0.chatId == id })
            try modelContext.delete(model: SDChat.self, where: #Predicate { $0.id == id })
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Стирает чаты в контексте этого актора. Каскад забирает их сообщения в базе.
    public func removeAll() throws(OrbitlError) {
        generation += 1
        do {
            try modelContext.delete(model: SDChat.self)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Сбрасывает счётчик непрочитанных локально и отправляет отметку на сервер.
    /// Если читать нечего, сервер не дёргается. Если сервер ответил ошибкой,
    /// локальное изменение остаётся, а ошибка пробрасывается.
    public func markAsRead(chatId: String) async throws(OrbitlError) {
        guard let mark = try markReadLocally(chatId: chatId) else { return }
        if case .failure(let error) = await api.markRead(chatId: chatId, messageId: mark.messageId) {
            throw error.orbitlError
        }
    }

    /// Сдвигает строку чата, когда пришло или ушло сообщение. `false`, если чата ещё нет в базе.
    ///
    /// Превью и время меняются, только если сообщение не старше строки: запоздавший пуш
    /// не откатывает список. `messageId == nil` (своё сообщение ещё в очереди) оставляет
    /// прежний `lastMessageId`, чтобы отметка прочтения не ушла с локальным id.
    /// `incoming` увеличивает счётчик; дубль пуша сюда приходит с `incoming == false`.
    public func noteMessage(chatId: String, messageId: String?, preview: String, at: Date, incoming: Bool) throws(OrbitlError) -> Bool {
        do {
            guard let chat = try chat(id: chatId) else { return false }
            if at >= chat.updatedAt {
                if let messageId { chat.lastMessageId = messageId }
                chat.preview = preview
                chat.updatedAt = at
            }
            if incoming { chat.unreadCount += 1 }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
        return true
    }

    /// Правка сообщения меняет превью, только если это последнее сообщение чата.
    /// Время строки не меняется: правка не поднимает чат в списке.
    public func noteEdit(chatId: String, messageId: String, text: String) throws(OrbitlError) {
        do {
            guard let chat = try chat(id: chatId), chat.lastMessageId == messageId, chat.preview != text else { return }
            chat.preview = text
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Последнее сообщение чата, как его знает строка списка.
    public func lastMessageId(chatId: String) -> String? {
        (try? chat(id: chatId))?.lastMessageId
    }

    /// Строка после удаления последнего сообщения, когда сервер недоступен:
    /// превью берётся из самого свежего сообщения в кэше, время строки не меняется.
    public func replaceLast(chatId: String, with message: MessageRecord?) throws(OrbitlError) {
        do {
            guard let chat = try chat(id: chatId) else { return }
            chat.lastMessageId = message?.serverId
            chat.preview = message?.text
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Своя отметка прочтения с другого устройства (пуш `read` с нашим id).
    ///
    /// `mark` — время прочитанного сообщения в миллисекундах. Счётчик обнуляется, только
    /// если отметка не раньше последнего сообщения строки, иначе после неё пришли новые
    /// и счётчик не трогается. `setAsUnread` — чат помечен непрочитанным вручную.
    public func applyOwnRead(chatId: String, mark: Int64, setAsUnread: Bool) throws(OrbitlError) {
        do {
            guard let chat = try chat(id: chatId) else { return }
            if setAsUnread {
                guard chat.unreadCount == 0 else { return }
                chat.unreadCount = 1
            } else {
                guard mark > 0, mark >= chat.updatedAt.unixMillis, chat.unreadCount != 0 else { return }
                chat.unreadCount = 0
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    private struct ReadMark {
        let messageId: String?
    }

    /// Отметка для сервера, если было что читать. Иначе `nil`.
    private func markReadLocally(chatId: String) throws(OrbitlError) -> ReadMark? {
        do {
            guard let chat = try chat(id: chatId), chat.unreadCount > 0 else { return nil }
            let messageId = chat.lastMessageId
            chat.unreadCount = 0
            try modelContext.save()
            notify()
            return ReadMark(messageId: messageId)
        } catch {
            throw .storageError
        }
    }

    /// База не очищалась с начала запроса. Иначе ответ устарел, и вызов считается отменённым.
    private func ensureCurrent(_ started: Int) throws(OrbitlError) {
        guard started == generation else { throw .cancelled }
    }

    /// Строки чатов с этими id, по id.
    private func chats(ids: [String]) throws -> [String: SDChat] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let rows = try modelContext.fetch(FetchDescriptor<SDChat>(predicate: #Predicate { wanted.contains($0.id) }))
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func chat(id: String) throws -> SDChat? {
        var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: Наблюдатели

    /// Подписчик мог уйти раньше, чем эта задача добралась до актора: тогда его снятие
    /// уже отработало, и сохранять его нельзя.
    private func addObserver(_ id: UUID, _ continuation: AsyncStream<[Chat]>.Continuation) {
        if case .terminated = continuation.yield(snapshot()) { return }
        observers[id] = continuation
    }

    /// Сколько подписчиков сейчас получают снимки. Для тестов.
    var observerCount: Int { observers.count }

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
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.id)]
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
            updatedAt: chat.updatedAt,
            preview: chat.preview
        )
    }
}
