import Foundation
import SwiftData
import OrbitleDomain

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
/// Swift 6: это `ModelActor` со своим фоновым контекстом. Макрос `@ModelActor`
/// не умеет инициализатор с `api`, поэтому `modelExecutor` и `modelContainer`
/// заданы явно. Модели SwiftData не покидают актор.
public actor MessageRepositoryImpl: MessageRepository, OutboxStore, ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public static let pageSize = 50

    private struct Observer {
        let chatId: String
        /// Пустая строка — основная лента, иначе id поста.
        let threadOf: String
        let continuation: AsyncStream<[Message]>.Continuation
    }

    private var observers: [UUID: Observer] = [:]
    /// Сколько последних сообщений показано в каждом чате.
    private var windows: [String: Int] = [:]
    /// Текущий автор исходящих. Задаётся после входа.
    private var currentUserId = ""
    private let api: any MaxAPI
    private var outbox: OutboxQueue?
    /// Растёт при каждой очистке базы. История, запрошенная до очистки, в базу не пишется.
    private var generation = 0
    /// Своё сообщение поставлено в очередь или ушло на сервер. Через это строка чата
    /// в списке сдвигается сразу, не дожидаясь пуша. Подключает `SyncEngine`.
    private var outgoingHandler: (@Sendable (OutgoingChange) async -> Void)?

    /// Что случилось со своим сообщением.
    public enum OutgoingChange: Sendable, Equatable {
        /// Записано локально и ждёт отправки.
        case queued(MessageRecord)
        /// Сервер принял, у записи уже есть `serverId` и время сервера.
        case sent(MessageRecord)
        /// Отправка не удалась, сообщение ждёт повтора.
        case failed(MessageRecord)
    }

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

    public func currentUser() -> String {
        currentUserId
    }

    public func setOutgoingHandler(_ handler: (@Sendable (OutgoingChange) async -> Void)?) {
        outgoingHandler = handler
    }

    // MARK: MessageRepository

    /// Сообщения чата от старых к новым, в пределах текущего окна.
    /// Первое значение приходит сразу из кэша.
    public nonisolated func messages(chatId: String) -> AsyncStream<[Message]> {
        stream(chatId: chatId, threadOf: "")
    }

    public nonisolated func comments(chatId: String, postId: String) -> AsyncStream<[Message]> {
        stream(chatId: chatId, threadOf: postId)
    }

    private nonisolated func stream(chatId: String, threadOf: String) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, chatId: chatId, threadOf: threadOf, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    /// Расширяет окно на одну страницу, при необходимости догружая историю с сервера.
    public func loadOlder(chatId: String) async throws(OrbitleError) {
        let shown = windows[chatId] ?? Self.pageSize
        let window = (try? fetchPage(chatId: chatId, before: nil, limit: shown)) ?? []
        _ = try await loadMore(chatId: chatId, before: window.last?.timestamp)
        windows[chatId] = shown + Self.pageSize
        notify(chatId: chatId)
    }

    /// Оптимистичная отправка: сообщение сразу попадает в базу со статусом `sending`
    /// и ставится в очередь. Результат отправки подписчики увидят через смену статуса.
    public func send(text: String, chatId: String) async throws(OrbitleError) {
        try await send(text: text, chatId: chatId, replyTo: nil)
    }

    /// Текст уходит в очередь. Цитата хранится локально: фасад пока отправляет только текст.
    public func send(text: String, chatId: String, replyTo: String?) async throws(OrbitleError) {
        let localId = "local-\(UUID().uuidString)"
        var content = MessageContent.empty
        if let replyTo, let target = (try? message(id: replyTo)) ?? (try? message(serverId: replyTo)) {
            let quoted = Self.record(target).domain
            let name = quoted.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
            content.reply = MessageReply(
                messageId: quoted.serverId ?? quoted.id,
                authorName: quoted.authorId == currentUserId ? "Вы" : (name.isEmpty ? "Сообщение" : name),
                preview: quoted.replySnippet,
                kind: quoted.replyKind
            )
        }
        let message = SDMessage(
            id: localId,
            chatId: chatId,
            authorId: currentUserId,
            text: text,
            timestamp: .now,
            status: .sending
        )
        message.contentJSON = MessageContentCodec.encode(content)
        do {
            message.chat = try chat(id: chatId)
            modelContext.insert(message)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: chatId)
        await outgoingHandler?(.queued(Self.record(message)))
        await outbox?.enqueue(localId)
    }

    public func setReaction(messageId: String, emoji: String) async throws(OrbitleError) {
        do {
            guard let message = try message(id: messageId) ?? message(serverId: messageId) else { return }
            var content = Self.content(of: message)
            content.reactions = content.reactions.toggled(emoji)
            message.contentJSON = MessageContentCodec.encode(content)
            try modelContext.save()
            notify(chatId: message.chatId)
        } catch {
            throw .storageError
        }
    }

    public func sendComment(text: String, chatId: String, postId: String) async throws(OrbitleError) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let comment = SDMessage(
            id: "local-\(UUID().uuidString)",
            chatId: chatId,
            authorId: currentUserId,
            text: body,
            timestamp: .now,
            status: .sent
        )
        comment.contentJSON = MessageContentCodec.encode(MessageContent(threadOf: postId))
        comment.threadOf = postId
        do {
            comment.chat = try chat(id: chatId)
            modelContext.insert(comment)
            if let parent = try message(id: postId) ?? message(serverId: postId) {
                var parentContent = Self.content(of: parent)
                parentContent.comments = CommentSummary(count: (parentContent.comments?.count ?? 0) + 1)
                parent.contentJSON = MessageContentCodec.encode(parentContent)
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: chatId)
    }

    /// Удаление: сначала сервер (для сообщений с серверным id), потом база. Если сервер
    /// отказал, сообщения остаются на месте и ошибка уходит на экран.
    public func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(OrbitleError) {
        let found = messageIds.compactMap { id in (try? message(id: id)) ?? (try? message(serverId: id)) }
        let localIds = found.map(\.id)
        let serverIds = found.compactMap { message -> String? in
            guard let serverId = message.serverId, Int64(serverId) != nil else { return nil }
            return serverId
        }
        if !serverIds.isEmpty {
            if case .failure(let error) = await api.deleteMessages(chatId: chatId, messageIds: serverIds, forEveryone: forEveryone) {
                Log.warning(.messages, "Сообщения не удалены: \(error)")
                throw error.orbitleError
            }
        }
        do {
            // После ожидания сервера строки перечитываются: база могла измениться.
            for id in localIds {
                if let message = try message(id: id) { modelContext.delete(message) }
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        Log.info(.messages, "Удалено сообщений: \(localIds.count)\(forEveryone ? " у всех" : " у себя")")
        notify(chatId: chatId)
    }

    /// Пересылка по серверному id. Новое сообщение сразу записывается в целевой чат.
    public func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(OrbitleError) {
        let stored = (try? message(id: messageId)) ?? (try? message(serverId: messageId))
        let serverId = stored?.serverId ?? messageId
        guard Int64(serverId) != nil else { throw .rejected("Сообщение ещё не отправлено") }
        switch await api.forwardMessage(toChatId: targetChatId, fromChatId: chatId, messageId: serverId) {
        case .success(let record):
            _ = try upsert([record])
            Log.info(.messages, "Сообщение переслано в чат \(targetChatId)")
        case .failure(let error):
            Log.warning(.messages, "Сообщение не переслано: \(error)")
            throw error.orbitleError
        }
    }

    public func noteDownloaded(messageId: String, attachmentId: String, localPath: String) async {
        guard let message = try? message(id: messageId) ?? message(serverId: messageId) else { return }
        var content = Self.content(of: message)
        content = content.settingLocalPath(localPath, attachmentId: attachmentId)
        message.contentJSON = MessageContentCodec.encode(content)
        try? modelContext.save()
        notify(chatId: message.chatId)
    }

    /// Комментарии поста, от старых к новым.
    public func commentPage(chatId: String, postId: String) throws(OrbitleError) -> [Message] {
        do {
            return try fetchThread(chatId: chatId, threadOf: postId, limit: 200).map { Self.record($0).domain }
        } catch {
            throw .storageError
        }
    }

    /// Повторная отправка сообщения со статусом `failed`.
    public func retry(messageId: String) async throws(OrbitleError) {
        guard let message = try? message(id: messageId), message.status == .failed else { return }
        do {
            message.status = .sending
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify(chatId: message.chatId)
        await outgoingHandler?(.queued(Self.record(message)))
        await outbox?.enqueue(messageId)
    }

    // MARK: Страницы (курсор по timestamp)

    /// Страница строго старше `before` (самые новые, если `nil`), от новых к старым.
    /// Сначала берётся из кэша. Если в кэше меньше `pageSize`, недостающее
    /// догружается с сервера, сохраняется и страница читается заново.
    /// Без сети возвращается то, что есть в кэше.
    public func loadMore(chatId: String, before: Date?) async throws(OrbitleError) -> [Message] {
        let local = try page(chatId: chatId, before: before)
        guard local.count < Self.pageSize else { return local.map(\.domain) }

        let cursor = local.last?.timestamp ?? before
        let started = generation
        let response = await api.fetchMessages(chatId: chatId, before: cursor, limit: Self.pageSize - local.count)
        try ensureCurrent(started)
        switch response {
        case .success(let records):
            guard !records.isEmpty else { return local.map(\.domain) }
            try upsert(records)
            return try page(chatId: chatId, before: before).map(\.domain)
        case .failure(.offline), .failure(.cancelled):
            return local.map(\.domain)
        case .failure(let error):
            if local.isEmpty { throw error.orbitleError }
            return local.map(\.domain)
        }
    }

    /// Самые свежие сообщения чата с сервера (для периодического опроса).
    public func fetchLatest(chatId: String) async throws(OrbitleError) {
        let started = generation
        switch await api.fetchMessages(chatId: chatId, before: nil, limit: Self.pageSize) {
        case .success(let records):
            try ensureCurrent(started)
            try upsert(records)
        case .failure(let error):
            throw error.orbitleError
        }
    }

    /// Страница из кэша, без обращения к серверу.
    public func page(chatId: String, before: Date?, limit: Int = pageSize) throws(OrbitleError) -> [MessageRecord] {
        do {
            return try fetchPage(chatId: chatId, before: before, limit: limit).map(Self.record)
        } catch {
            throw .storageError
        }
    }

    // MARK: Запись (вызывается из SyncEngine)

    /// Вставляет новые сообщения и обновляет существующие. Сообщение с сервера
    /// совпадает с локальным по `id` или по `serverId` (своё отправленное).
    /// Возвращает id действительно вставленных записей: повторный пуш того же
    /// сообщения ничего не вставляет и не должен второй раз увеличить счётчик.
    @discardableResult
    public func upsert(_ records: [MessageRecord]) throws(OrbitleError) -> Set<String> {
        var touched = Set<String>()
        var inserted = Set<String>()
        do {
            // Три выборки на весь пакет (по id, по серверному id и чаты), а не по три на запись.
            var byId = try messages(ids: records.map(\.id))
            var byServerId = try messages(serverIds: records.map { $0.serverId ?? $0.id })
            let chatRows = try chats(ids: records.map(\.chatId))
            for record in records {
                if let message = byId[record.id] ?? byServerId[record.serverId ?? record.id] {
                    message.text = record.text
                    message.status = record.status
                    message.mediaId = record.mediaId
                    // Пустой фрагмент значит «фасад его не прислал», а не «вложений больше нет».
                    if !record.contentJSON.isEmpty {
                        message.contentJSON = record.contentJSON
                        message.threadOf = record.threadOf
                    }
                    if !record.authorName.isEmpty { message.authorName = record.authorName }
                    if !record.authorAvatarURL.isEmpty { message.authorAvatarURL = record.authorAvatarURL }
                    if let serverId = record.serverId {
                        message.serverId = serverId
                        byServerId[serverId] = message
                    }
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
                    message.contentJSON = record.contentJSON
                    message.threadOf = record.threadOf
                    message.authorName = record.authorName
                    message.authorAvatarURL = record.authorAvatarURL
                    message.chat = chatRows[record.chatId]
                    modelContext.insert(message)
                    byId[record.id] = message
                    byServerId[record.serverId ?? record.id] = message
                    inserted.insert(record.id)
                }
                touched.insert(record.chatId)
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        touched.forEach(notify(chatId:))
        return inserted
    }

    /// Правка из пуша. Текст меняется всегда. Пустой фрагмент и пустое имя не затирают
    /// то, что уже лежит в базе: фасад мог прислать только новый текст.
    /// `false`, если сообщения в кэше нет — правка не становится новым сообщением.
    @discardableResult
    public func applyEdit(_ record: MessageRecord) throws(OrbitleError) -> Bool {
        do {
            guard let message = try message(id: record.id) ?? message(serverId: record.serverId ?? record.id) else { return false }
            message.text = record.text
            if let mediaId = record.mediaId { message.mediaId = mediaId }
            if !record.contentJSON.isEmpty {
                message.contentJSON = record.contentJSON
                message.threadOf = record.threadOf
            }
            if !record.authorName.isEmpty { message.authorName = record.authorName }
            if !record.authorAvatarURL.isEmpty { message.authorAvatarURL = record.authorAvatarURL }
            try modelContext.save()
            notify(chatId: message.chatId)
            return true
        } catch {
            throw .storageError
        }
    }

    /// Самое свежее сообщение чата в кэше.
    public func latest(chatId: String) -> MessageRecord? {
        ((try? fetchPage(chatId: chatId, before: nil, limit: 1)) ?? []).first.map(Self.record)
    }

    /// Стирает сообщения в контексте этого актора. Выход зовёт это до удаления чатов.
    public func removeAll() throws(OrbitleError) {
        generation += 1
        do {
            try modelContext.delete(model: SDMessage.self)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        let chatIds = Set(observers.values.map(\.chatId))
        windows.removeAll()
        for chatId in chatIds {
            notify(chatId: chatId)
        }
    }

    public func delete(messageId: String) throws(OrbitleError) {
        do {
            guard let message = try message(id: messageId) ?? message(serverId: messageId) else { return }
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

    public func markSent(localId: String, serverId: String, timestamp: Date) async {
        guard let message = try? message(id: localId) else { return }
        // Эхо своего сообщения (пуш или опрос истории) могло прийти раньше ответа на отправку
        // и лечь отдельной строкой с серверным id. Остаётся локальная строка: экран уже
        // показывает её под локальным id.
        for echo in (try? echoes(of: serverId, except: localId)) ?? [] {
            modelContext.delete(echo)
        }
        message.status = .sent
        message.serverId = serverId
        message.timestamp = timestamp
        try? modelContext.save()
        notify(chatId: message.chatId)
        await outgoingHandler?(.sent(Self.record(message)))
    }

    public func markFailed(localId: String) async {
        guard let message = try? message(id: localId) else { return }
        message.status = .failed
        try? modelContext.save()
        notify(chatId: message.chatId)
        await outgoingHandler?(.failed(Self.record(message)))
    }

    // MARK: Внутреннее

    /// База не очищалась с начала запроса. Иначе ответ устарел, и вызов считается отменённым.
    private func ensureCurrent(_ started: Int) throws(OrbitleError) {
        guard started == generation else { throw .cancelled }
    }

    func message(id: String) throws -> SDMessage? {
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Строки с тем же серверным id, кроме `localId`.
    private func echoes(of serverId: String, except localId: String) throws -> [SDMessage] {
        let optionalId: String? = serverId
        let descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.id == serverId || $0.serverId == optionalId }
        )
        return try modelContext.fetch(descriptor).filter { $0.id != localId }
    }

    private func message(serverId: String) throws -> SDMessage? {
        let optionalId: String? = serverId
        var descriptor = FetchDescriptor<SDMessage>(predicate: #Predicate { $0.serverId == optionalId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Сообщения с этими локальными id, по id.
    private func messages(ids: [String]) throws -> [String: SDMessage] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let rows = try modelContext.fetch(FetchDescriptor<SDMessage>(predicate: #Predicate { wanted.contains($0.id) }))
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Сообщения с этими серверными id, по серверному id.
    private func messages(serverIds: [String]) throws -> [String: SDMessage] {
        guard !serverIds.isEmpty else { return [:] }
        let wanted = Array(Set(serverIds))
        let rows = try modelContext.fetch(FetchDescriptor<SDMessage>(predicate: #Predicate { message in
            message.serverId.flatMap { serverId in wanted.contains(serverId) } ?? false
        }))
        var result: [String: SDMessage] = [:]
        for row in rows {
            guard let serverId = row.serverId, result[serverId] == nil else { continue }
            result[serverId] = row
        }
        return result
    }

    private func chats(ids: [String]) throws -> [String: SDChat] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let rows = try modelContext.fetch(FetchDescriptor<SDChat>(predicate: #Predicate { wanted.contains($0.id) }))
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func fetchPage(chatId: String, before: Date?, limit: Int) throws -> [SDMessage] {
        let id = chatId
        let root = ""
        let predicate: Predicate<SDMessage>
        if let cursor = before {
            predicate = #Predicate { $0.chatId == id && $0.threadOf == root && $0.timestamp < cursor }
        } else {
            predicate = #Predicate { $0.chatId == id && $0.threadOf == root }
        }
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func fetchThread(chatId: String, threadOf: String, limit: Int) throws -> [SDMessage] {
        let id = chatId
        let thread = threadOf
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.chatId == id && $0.threadOf == thread },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func chat(id: String) throws -> SDChat? {
        var descriptor = FetchDescriptor<SDChat>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Подписчик мог уйти раньше, чем эта задача добралась до актора: тогда его снятие
    /// уже отработало, и сохранять его нельзя.
    private func addObserver(_ id: UUID, chatId: String, threadOf: String, _ continuation: AsyncStream<[Message]>.Continuation) {
        if case .terminated = continuation.yield(snapshot(chatId: chatId, threadOf: threadOf)) { return }
        observers[id] = Observer(chatId: chatId, threadOf: threadOf, continuation: continuation)
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notify(chatId: String) {
        let targets = observers.values.filter { $0.chatId == chatId }
        guard !targets.isEmpty else { return }
        var cache: [String: [Message]] = [:]
        for observer in targets {
            if cache[observer.threadOf] == nil {
                cache[observer.threadOf] = snapshot(chatId: chatId, threadOf: observer.threadOf)
            }
            if let messages = cache[observer.threadOf] {
                observer.continuation.yield(messages)
            }
        }
    }

    /// Основная лента — последние сообщения окна от старых к новым. Тред — хронологически.
    private func snapshot(chatId: String, threadOf: String) -> [Message] {
        if threadOf.isEmpty {
            let limit = windows[chatId] ?? Self.pageSize
            let newestFirst = (try? fetchPage(chatId: chatId, before: nil, limit: limit)) ?? []
            return newestFirst.reversed().map { Self.record($0).domain }
        }
        let rows = (try? fetchThread(chatId: chatId, threadOf: threadOf, limit: 200)) ?? []
        return rows.map { Self.record($0).domain }
    }

    private static func content(of message: SDMessage) -> MessageContent {
        var content = MessageContentCodec.decode(message.contentJSON)
        if !message.threadOf.isEmpty { content.threadOf = message.threadOf }
        return content
    }

    private static func record(_ message: SDMessage) -> MessageRecord {
        let content = content(of: message)
        return MessageRecord(
            id: message.id,
            serverId: message.serverId,
            chatId: message.chatId,
            authorId: message.authorId,
            text: message.text,
            timestamp: message.timestamp,
            status: message.status,
            mediaId: message.mediaId,
            contentJSON: MessageContentCodec.encode(content),
            threadOf: content.threadOf ?? "",
            authorName: message.authorName,
            authorAvatarURL: message.authorAvatarURL
        )
    }
}
