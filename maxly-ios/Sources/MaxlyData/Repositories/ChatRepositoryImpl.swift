import Foundation
import SwiftData
import MaxlyDomain

/// Реализация `ChatRepository` поверх SwiftData.
///
/// Swift 6: модели SwiftData не Sendable, поэтому репозиторий — `ModelActor`
/// со своим фоновым `ModelContext`. Макрос `@ModelActor` всегда добавляет
/// `init(modelContainer:)` и не видит `api`, поэтому соответствие написано вручную.
/// Наружу выходят только доменные модели и Sendable-записи.
public actor ChatRepositoryImpl: ChatRepository, ChatDraftStore, ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    private var observers: [UUID: AsyncStream<[Chat]>.Continuation] = [:]
    /// Отметка прочтения собеседника выросла: сообщения чата перерисовывают галочки.
    private var peerReadHandler: (@Sendable (String, Int64) async -> Void)?
    /// Переписка стёрта в этом контексте: лента открытого чата живёт в другом акторе.
    private var historyDropped: (@Sendable (String) async -> Void)?
    private var typingObservers: [UUID: AsyncStream<[String: [TypingActivity]]>.Continuation] = [:]
    /// Кто печатает и до каких пор (правила сроков — в `TypingTracker`).
    private var typingTracker: TypingTracker
    private var typingExpiry: Task<Void, Never>?
    /// Имена печатающих из сохранённых сообщений: id пользователя → имя. Пустых нет.
    private var typingNames: [String: String] = [:]
    private let clock: @Sendable () -> Date
    private nonisolated let api: any MaxAPI
    /// Растёт при каждой очистке базы. Ответ сервера на запрос, начатый до очистки
    /// (например, до выхода), в базу уже не пишется.
    private var generation = 0
    /// Диалоги, открытые из контактов, которых ещё нет в базе: id чата → черновик.
    private var pendingDialogs: [String: DialogDraft] = [:]
    /// Когда чат последний раз записан в базу: сверка полного списка не трогает чаты, записанные
    /// уже после запроса (только что созданный, пришедший пушем).
    private var lastWrites: [String: Date] = [:]
    /// Свои переключения звука: id чата → когда переключён или когда пришёл ответ сервера.
    /// Ответ списка или `CHAT_INFO`, запрошенный раньше, звук этого чата не трогает: ядро
    /// считает его по конфигу, который мог ещё не получить новое значение, и метка «без звука»
    /// слетала до следующего опроса.
    private var muteToggles: [String: Date] = [:]
    /// Временные выключения звука: id чата → задача, которая включит звук в конце срока.
    /// Отдельного события об окончании ядро не шлёт.
    private var muteExpiries: [String: (until: Int64, task: Task<Void, Never>)] = [:]
    /// Свои отметки прочтения (мс): ответы сервера на отметки, пуши с других устройств и
    /// местная отметка ядра. Запоздавший ответ на более старую отметку не применяется.
    private nonisolated let readMarkBook = OwnReadMarkBook()

    /// Закреплённые чаты сервера сверху вниз, как их прислало ядро (`nil`, пока неизвестны).
    /// В списке могут быть чаты, которых ещё нет в базе: строка получит место, когда появится.
    private var serverPins: [String]?
    /// Список, отправленный на сервер последним и ещё не подтверждённый. Следующее действие
    /// строится от него, иначе два быстрых закрепления потеряли бы первое.
    private var requestedPins: [String]?
    private var pinRequests = 0

    /// Закрепление и порядок закреплённых синхронизируются с сервером (папка «Все чаты»),
    /// ручная пометка «непрочитано» хранится на устройстве. Остальное (звук, архив, удаление,
    /// поиск, страницы) доступно, только если его умеет `api`.
    public nonisolated let capabilities: ChatListCapabilities

    /// `typingTTL` — сколько держать «печатает…» без повторного пуша (8 с, как у веб-клиента Max).
    public init(
        modelContainer: ModelContainer,
        api: any MaxAPI,
        typingTTL: TimeInterval = TypingTracker.defaultTTL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
        self.typingTracker = TypingTracker(ttl: typingTTL)
        self.clock = clock
        self.capabilities = [.pin, .reorderPins, .markUnread, .mute, .serverSearch, .delete]
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
    public func refresh() async throws(MaxlyError) {
        let started = generation
        let requestedAt = Date()
        switch await api.fetchChatList() {
        case .success(let page):
            try ensureCurrent(started)
            try upsert(keepingLocalMute(page.records.filter(\.isActive), requestedAt: requestedAt))
            for record in page.records where !record.isActive {
                await dropInactive(chatId: record.id)
            }
            if page.complete {
                await dropMissing(keeping: Set(page.records.map(\.id)), requestedAt: requestedAt)
            }
        case .failure(let error):
            throw error.maxlyError
        }
    }

    /// Сверка с полным списком сервера: чаты, которых в нём нет, аккаунт покинул или удалил на
    /// другом устройстве (пуша об этом может не быть). Они уходят вместе с историей.
    /// Не трогаются «Избранное» и чаты, записанные уже после запроса.
    private func dropMissing(keeping ids: Set<String>, requestedAt: Date) async {
        guard let rows = try? modelContext.fetch(FetchDescriptor<SDChat>()) else { return }
        let stale = rows.map(\.id).filter { id in
            !ids.contains(id) && id != Chat.savedMessagesId && (lastWrites[id].map { $0 < requestedAt } ?? true)
        }
        guard !stale.isEmpty else { return }
        for id in stale {
            do {
                try delete(chatId: id)
            } catch {
                Log.info(.chats, "Чат \(id), которого нет на сервере, не убран: \(error)")
                continue
            }
            await historyDropped?(id)
        }
        Log.info(.chats, "Убрано чатов, которых нет в списке сервера: \(stale.count)")
    }

    /// Чат, в котором аккаунт больше не участвует (вышел, чат закрыт): уходит из списка вместе
    /// с историей, как в Komet. Сервер не даёт из такого чата выйти или удалить его, а историю
    /// отдаёт отказом `too.many.requests`.
    public func dropInactive(chatId: String) async {
        guard (try? chats(ids: [chatId]))?[chatId] != nil else { return }
        do {
            try delete(chatId: chatId)
        } catch {
            Log.info(.chats, "Неактивный чат \(chatId) не убран: \(error)")
            return
        }
        Log.info(.chats, "Неактивный чат \(chatId) убран из списка")
        await historyDropped?(chatId)
    }

    /// Один чат с сервера (`CHAT_INFO`).
    public func refresh(chatId: String) async throws(MaxlyError) {
        let started = generation
        let requestedAt = Date()
        switch await api.fetchChat(id: chatId) {
        case .success(let record):
            try ensureCurrent(started)
            try upsert(keepingLocalMute([record], requestedAt: requestedAt))
        case .failure(let error):
            throw error.maxlyError
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
    public func setPeerReadHandler(_ handler: (@Sendable (String, Int64) async -> Void)?) {
        peerReadHandler = handler
    }

    public func setHistoryDroppedHandler(_ handler: (@Sendable (String) async -> Void)?) {
        historyDropped = handler
    }

    public func upsert(_ records: [ChatRecord]) throws(MaxlyError) {
        var raised: [(String, Int64)] = []
        do {
            // Одна выборка на весь пакет, а не по запросу на каждую запись.
            var existing = try chats(ids: records.map(\.id))
            defer { reportPeerRead(raised) }
            let now = Date()
            for record in records {
                lastWrites[record.id] = now
                if record.peerReadMark > 0, let chat = existing[record.id], record.peerReadMark > chat.peerReadMark {
                    chat.peerReadMark = record.peerReadMark
                    raised.append((record.id, record.peerReadMark))
                }
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
                    chat.lastAuthorId = record.lastAuthorId
                    chat.lastAuthorName = record.lastAuthorName
                    chat.lastOutgoing = record.lastOutgoing ?? false
                    chat.lastForwarded = record.lastForwarded
                    chat.lastMediaRaw = record.lastMedia?.rawValue
                    chat.lastThumbnailURLString = record.lastThumbnailURL?.absoluteString
                    Self.mergeFlags(record, into: chat)
                    chat.peerReadMark = record.peerReadMark
                    chat.lastMessageAt = record.lastMessageAt
                    if record.peerReadMark > 0 { raised.append((record.id, record.peerReadMark)) }
                    modelContext.insert(chat)
                    existing[record.id] = chat
                }
                // Строки списка приходят без закрепления: место берётся из списка сервера.
                if !record.pinsKnown, let serverPins, let chat = existing[record.id] {
                    chat.pinOrder = serverPins.firstIndex(of: record.id)
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
        mergeFlags(record, into: chat)
        // Сервер говорит, что сообщений нет (всё удалено): превью удалённого не остаётся.
        // Своё сообщение, которое ещё отправляется, не трогается.
        if record.lastKnown, record.lastMessageId == nil, chat.lastMessageId != nil || chat.preview != nil,
           chat.lastLocalId == nil {
            chat.lastMessageId = nil
            chat.preview = nil
            chat.lastAuthorId = nil
            chat.lastAuthorName = nil
            chat.lastOutgoing = false
            chat.lastDeliveryRaw = nil
            chat.lastForwarded = false
            chat.lastMediaRaw = nil
            chat.lastThumbnailURLString = nil
            chat.lastMessageAt = 0
            return
        }
        guard record.updatedAt >= chat.updatedAt else { return }
        if let lastMessageId = record.lastMessageId {
            if lastMessageId != chat.lastMessageId {
                // Сменилось последнее сообщение: прежние автор и галочки к нему не относятся.
                chat.lastAuthorId = record.lastAuthorId
                chat.lastAuthorName = record.lastAuthorName
                chat.lastOutgoing = record.lastOutgoing ?? false
                chat.lastForwarded = record.lastForwarded
                chat.lastDeliveryRaw = nil
                chat.lastLocalId = nil
                chat.lastMediaRaw = record.lastMedia?.rawValue
                chat.lastThumbnailURLString = record.lastThumbnailURL?.absoluteString
                // И текст — тоже нового сообщения. У фото без подписи или голосового текста
                // нет (`nil`), и раньше в строке оставался текст прежнего сообщения вместо
                // «Фотографии»: превью переписывалось только непустым.
                chat.preview = record.preview
                // Время нового сообщения. Пуш чата его не несёт (`0`): прежнее к нему не относится.
                chat.lastMessageAt = record.lastMessageAt
            } else {
                if record.lastMessageAt > 0 { chat.lastMessageAt = record.lastMessageAt }
                if let author = record.lastAuthorId { chat.lastAuthorId = author }
                if let name = record.lastAuthorName { chat.lastAuthorName = name }
                if let outgoing = record.lastOutgoing { chat.lastOutgoing = outgoing }
                chat.lastForwarded = record.lastForwarded
                if let media = record.lastMedia {
                    chat.lastMediaRaw = media.rawValue
                    chat.lastThumbnailURLString = record.lastThumbnailURL?.absoluteString
                }
            }
            chat.lastMessageId = lastMessageId
        }
        if let preview = record.preview { chat.preview = preview }
        chat.updatedAt = record.updatedAt
        chat.unreadCount = max(record.unreadCount, 0)
    }

    /// Флаги, которые сервер присылает не всегда: `nil` оставляет известное значение.
    /// Закрепление с сервера заменяет локальное, только если сервер его прислал.
    private static func mergeFlags(_ record: ChatRecord, into chat: SDChat) {
        if let url = record.avatarURL { chat.avatarURLString = url.absoluteString }
        if let muted = record.isMuted { chat.isMuted = muted }
        if let archived = record.isArchived { chat.isArchived = archived }
        if let bot = record.isBot { chat.isBot = bot }
        if let webApp = record.hasWebApp { chat.hasWebApp = webApp }
        if let verified = record.isVerified { chat.isVerified = verified }
        if let comments = record.commentsEnabled { chat.commentsOption = comments ? 1 : 0 }
        if let canWrite = record.canWrite { chat.canWriteOption = canWrite ? 1 : 0 }
        if record.pinsKnown { chat.pinOrder = record.pinOrder }
    }

    /// Удаляет чат вместе с сообщениями. Сообщения без связи с чатом (записанные раньше
    /// самого чата) каскад не видит, поэтому они удаляются по `chatId` явно.
    ///
    /// Строка чата удаляется объектом, а не пакетным `delete(model:where:)`: пакетное удаление
    /// в контексте, где только что удалены его сообщения, на iOS 27 роняло процесс внутри
    /// SwiftData (сбой по сигналу 5 после «Удалить чат»).
    public func delete(chatId: String) throws(MaxlyError) {
        do {
            let id = chatId
            try modelContext.deleteInstances(model: SDMessage.self, where: #Predicate { $0.chatId == id })
            if let chat = try chat(id: chatId) {
                modelContext.delete(chat)
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Стирает чаты в контексте этого актора. Каскад забирает их сообщения в базе.
    public func removeAll() throws(MaxlyError) {
        generation += 1
        readMarkBook.removeAll()
        muteToggles.removeAll()
        muteExpiries.values.forEach { $0.task.cancel() }
        muteExpiries.removeAll()
        serverPins = nil
        requestedPins = nil
        pendingDialogs.removeAll()
        typingTracker.removeAll()
        typingNames.removeAll()
        publishTyping()
        do {
            // По одному, как в `delete(chatId:)`: пакетное удаление по живому контексту
            // небезопасно. Сообщения к этому времени уже стёрты, каскаду почти нечего делать.
            try modelContext.deleteInstances(model: SDChat.self)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Сбрасывает счётчик непрочитанных локально и отправляет отметку на сервер.
    /// Если читать нечего, сервер не дёргается. Если сервер ответил ошибкой,
    /// локальное изменение остаётся, а ошибка пробрасывается.
    ///
    /// Отметка — серверное время последнего сообщения, а не часы устройства: часы могут
    /// отставать, и только что пришедшие сообщения остались бы непрочитанными на сервере и у
    /// собеседника. Ответ сервера применяется сразу, не дожидаясь пуша (`applyReadReply`).
    public func markAsRead(chatId: String) async throws(MaxlyError) {
        guard let mark = try markReadLocally(chatId: chatId) else { return }
        let started = generation
        let reply: CoreReadMark?
        switch await api.markRead(chatId: chatId, messageId: mark.messageId, at: mark.time) {
        case .success(let value): reply = value
        case .failure(let error): throw error.maxlyError
        }
        guard let reply, started == generation else { return }
        try applyReadReply(chatId: chatId, reply: reply, lastBefore: mark.messageId)
    }

    /// Прочитать чат до увиденного сообщения (экран чата, `ReadMarkScheduler`). Если читать
    /// нечего (непрочитанных нет), сервер не дёргается. Отметка дошла до последнего сообщения
    /// строки — бейдж пропадает сразу; иначе счётчик берётся из ответа сервера: ниже отметки
    /// могут остаться непрочитанные.
    public func markRead(chatId: String, messageId: String, at mark: Int64) async throws(MaxlyError) {
        let lastBefore: String?
        do {
            guard let chat = try chat(id: chatId), chat.unreadCount > 0 else { return }
            lastBefore = chat.lastMessageId
            if mark >= ReadMarks.readTime(lastMessageAt: chat.lastMessageAt, updatedAt: chat.updatedAt) {
                chat.unreadCount = 0
                try modelContext.save()
                notify()
            }
        } catch {
            throw .storageError
        }
        let started = generation
        let reply: CoreReadMark?
        switch await api.markRead(chatId: chatId, messageId: messageId, at: mark) {
        case .success(let value): reply = value
        case .failure(let error): throw error.maxlyError
        }
        guard let reply, started == generation else { return }
        try applyReadReply(chatId: chatId, reply: reply, lastBefore: lastBefore)
    }

    /// Своя позиция чата (`OwnReadMark`): ответ сервера, пуш и местная отметка ядра.
    public nonisolated func ownReadMark(chatId: String) -> Int64 {
        readMarkBook.position(chatId)
    }

    /// Местная отметка ядра, пока отметки о прочтении скрыты (`GhostControls.localReadMark`).
    public nonisolated func setLocalReadMarks(_ source: (@Sendable (String) -> Int64)?) {
        readMarkBook.setLocal(source)
    }

    /// Ответ сервера на свою отметку. Ответ старее уже применённой отметки пропускается:
    /// ответы на две отметки подряд могут прийти в обратном порядке. Счётчик сервера берётся,
    /// только если он меньше локального и с запроса в чат ничего не пришло (`lastBefore` —
    /// последнее сообщение на момент отметки): новое сообщение остаётся непрочитанным.
    func applyReadReply(chatId: String, reply: CoreReadMark, lastBefore: String?) throws(MaxlyError) {
        guard ReadMarks.isFresh(reply.mark, known: readMarkBook.known(chatId)) else { return }
        readMarkBook.noteReply(reply.mark, chatId: chatId)
        do {
            guard let chat = try chat(id: chatId),
                  let unread = ReadMarks.unreadAfterRead(
                      local: chat.unreadCount, lastNow: chat.lastMessageId, lastBefore: lastBefore, server: reply.unread
                  ) else { return }
            chat.unreadCount = unread
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Чат непрочитан на сервере начиная с сообщения в `date`. Счётчик в базе — ответ сервера,
    /// но не меньше одного: как у пуша «непрочитано» с другого устройства.
    public func markUnread(chatId: String, from date: Date) async throws(MaxlyError) {
        let started = generation
        let unread: Int
        switch await api.markUnread(chatId: chatId, from: date) {
        case .success(let count): unread = count
        case .failure(let error): throw error.maxlyError
        }
        try ensureCurrent(started)
        // Отметка сервера ушла назад: следующий ответ на прочтение сравнивается уже не с ней.
        readMarkBook.forget(chatId)
        do {
            guard let chat = try chat(id: chatId) else { return }
            chat.unreadCount = max(unread, 1)
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Сдвигает строку чата, когда пришло или ушло сообщение. `false`, если чата ещё нет в базе.
    ///
    /// Превью и время меняются, только если сообщение не старше строки: запоздавший пуш
    /// не откатывает список. `messageId == nil` (своё сообщение ещё в очереди) оставляет
    /// прежний `lastMessageId`, чтобы отметка прочтения не ушла с локальным id.
    /// `incoming` увеличивает счётчик; дубль пуша сюда приходит с `incoming == false`.
    ///
    /// `authorId`, `outgoing` и `delivery` описывают сообщение для строки: автор в группе
    /// и галочки своего сообщения.
    public func noteMessage(
        chatId: String,
        messageId: String?,
        preview: String,
        at: Date,
        incoming: Bool,
        authorId: String? = nil,
        outgoing: Bool = false,
        delivery: DeliveryState? = nil,
        localId: String? = nil,
        media: MessageMediaKind? = nil,
        thumbnail: URL? = nil,
        authorName: String? = nil,
        forwarded: Bool = false
    ) throws(MaxlyError) -> Bool {
        do {
            guard let chat = try chat(id: chatId) ?? insertPendingDialog(chatId: chatId, at: at) else { return false }
            if at >= chat.updatedAt {
                if let messageId { chat.lastMessageId = messageId }
                chat.preview = preview
                chat.updatedAt = at
                chat.lastMessageAt = at.unixMillis
                chat.lastAuthorId = authorId
                chat.lastOutgoing = outgoing
                chat.lastDeliveryRaw = outgoing ? (delivery ?? .sent).rawValue : nil
                chat.lastLocalId = localId
                chat.lastMediaRaw = media?.rawValue
                chat.lastThumbnailURLString = thumbnail?.absoluteString
                chat.lastAuthorName = authorName
                chat.lastForwarded = forwarded
            }
            if incoming { chat.unreadCount += 1 }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
        return true
    }

    /// `async`, как в протоколе: иначе в асинхронном контексте Swift выбрал бы пустую
    /// реализацию по умолчанию из расширения протокола, а не эту.
    public func prepareDialog(_ draft: DialogDraft) async {
        pendingDialogs[draft.chatId] = draft
    }

    /// `async`, как у `prepareDialog`: иначе Swift взял бы пустую реализацию протокола.
    public func createGroup(title: String, memberIds: [String]) async throws(MaxlyError) -> String? {
        try await storeCreated(await api.createGroup(title: title, memberIds: memberIds))
    }

    public func createChannel(title: String) async throws(MaxlyError) -> String? {
        try await storeCreated(await api.createChannel(title: title))
    }

    public func members(chatId: String) async throws(MaxlyError) -> [ChatMemberRef] {
        switch await api.chatMembers(chatId: chatId) {
        case .success(let rows):
            return rows.map { ChatMemberRef(id: $0.id, name: $0.name) }
        case .failure(let error):
            throw error.maxlyError
        }
    }

    public func botCommands(botId: String) async throws(MaxlyError) -> [BotCommandRef] {
        switch await api.botCommands(botId: botId) {
        case .success(let rows):
            return rows.map { BotCommandRef(name: $0.name, summary: $0.summary) }
        case .failure(let error):
            throw error.maxlyError
        }
    }

    public func pressButton(chatId: String, messageId: String, callbackId: String, payload: String?) async throws(MaxlyError) -> BotButtonAnswer {
        switch await api.pressButton(chatId: chatId, messageId: messageId, callbackId: callbackId, payload: payload) {
        case .success(let answer):
            let text = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return BotButtonAnswer(text: text.isEmpty ? nil : text, url: answer.url.isEmpty ? nil : URL(string: answer.url))
        case .failure(let error):
            throw error.maxlyError
        }
    }

    public func joinByLink(_ link: String) async throws(MaxlyError) -> String? {
        try await storeCreated(await api.joinByLink(link))
    }

    /// `async`, как у `prepareDialog`: иначе Swift взял бы пустую реализацию протокола.
    public func delete(chatId: String, forEveryone: Bool) async throws(MaxlyError) {
        let started = generation
        let time = try eventTimeMs(chatId)
        if case .failure(let error) = await api.deleteChat(chatId: chatId, lastEventTimeMs: time, forEveryone: forEveryone) {
            throw error.maxlyError
        }
        try ensureCurrent(started)
        try delete(chatId: chatId)
        await historyDropped?(chatId)
    }

    public func leave(chatId: String) async throws(MaxlyError) {
        let started = generation
        if case .failure(let error) = await api.leaveChat(chatId: chatId) {
            throw error.maxlyError
        }
        try ensureCurrent(started)
        try delete(chatId: chatId)
        await historyDropped?(chatId)
    }

    public func clearHistory(chatId: String, forEveryone: Bool) async throws(MaxlyError) {
        let started = generation
        let time = try eventTimeMs(chatId)
        if case .failure(let error) = await api.clearHistory(chatId: chatId, lastEventTimeMs: time, forEveryone: forEveryone) {
            throw error.maxlyError
        }
        try ensureCurrent(started)
        try wipeMessages(chatId: chatId)
        await historyDropped?(chatId)
    }

    /// Время последнего события чата, мс. Если строки нет — текущие часы.
    private func eventTimeMs(_ chatId: String) throws(MaxlyError) -> Int64 {
        do {
            let ms = (try chat(id: chatId))?.updatedAt.unixMillis ?? 0
            return ms > 0 ? ms : Int64(Date().timeIntervalSince1970 * 1000)
        } catch {
            throw .storageError
        }
    }

    /// Сообщения стираются, строка чата остаётся без превью и счётчика.
    private func wipeMessages(chatId: String) throws(MaxlyError) {
        do {
            let id = chatId
            try modelContext.deleteInstances(model: SDMessage.self, where: #Predicate { $0.chatId == id })
            if let chat = try chat(id: chatId) {
                chat.lastMessageId = nil
                chat.preview = nil
                chat.unreadCount = 0
                chat.lastAuthorId = nil
                chat.lastOutgoing = false
                chat.lastLocalId = nil
                chat.lastDeliveryRaw = nil
                chat.lastMediaRaw = nil
                chat.lastThumbnailURLString = nil
                chat.lastAuthorName = nil
                chat.lastForwarded = false
                chat.isMarkedUnread = false
            }
            try modelContext.save()
        } catch let error as MaxlyError {
            throw error
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Чат из ответа сервера сразу попадает в список. `nil` — ответа с чатом не было.
    private func storeCreated(_ result: Result<ChatRecord?, MaxAPIError>) async throws(MaxlyError) -> String? {
        let started = generation
        switch result {
        case .success(let record):
            guard let record, !record.id.isEmpty else { return nil }
            try ensureCurrent(started)
            try upsert([record])
            return record.id
        case .failure(let error):
            throw error.maxlyError
        }
    }

    /// Строка для диалога из `prepareDialog`, когда в нём появилось первое сообщение.
    /// Сервер пришлёт свою строку позже, она сольётся с этой по id.
    private func insertPendingDialog(chatId: String, at: Date) throws -> SDChat? {
        guard let draft = pendingDialogs.removeValue(forKey: chatId) else { return nil }
        Log.info(.chats, "Новый диалог \(chatId) появился в списке")
        let chat = SDChat(
            id: chatId,
            title: draft.title,
            type: .private,
            lastMessageId: nil,
            unreadCount: 0,
            updatedAt: at,
            preview: nil
        )
        chat.avatarURLString = draft.avatarURL?.absoluteString
        modelContext.insert(chat)
        return chat
    }

    /// Правка сообщения меняет превью, только если это последнее сообщение чата.
    /// Время строки не меняется: правка не поднимает чат в списке.
    public func noteEdit(chatId: String, messageId: String, text: String) throws(MaxlyError) {
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

    /// Строка после удаления последнего сообщения: превью, автор, вложение и время — самого
    /// свежего сообщения в кэше. Без сообщений время строки не меняется. Время откатывается
    /// назад, иначе следующий ответ списка (он старше) не смог бы обновить строку.
    public func replaceLast(chatId: String, with message: MessageRecord?, currentUser: String = "") throws(MaxlyError) {
        do {
            guard let chat = try chat(id: chatId) else { return }
            chat.lastMessageId = message?.serverId
            let author = message.flatMap { $0.authorId.isEmpty ? nil : $0.authorId }
            chat.lastAuthorId = author
            chat.lastOutgoing = author != nil && author == currentUser
            chat.lastDeliveryRaw = chat.lastOutgoing ? DeliveryState.sent.rawValue : nil
            chat.preview = message?.text
            // Вид вложения и миниатюра — нового последнего сообщения, иначе строка
            // продолжает показывать «Фотографию» удалённого.
            let content = message.map { MessageContentCodec.decode($0.contentJSON) }
            chat.lastMediaRaw = content?.previewMedia?.rawValue
            chat.lastThumbnailURLString = content?.previewThumbnail?.absoluteString
            chat.lastForwarded = content?.forward != nil
            chat.lastAuthorName = message.flatMap { $0.authorName.isEmpty ? nil : $0.authorName }
            if let forwarded = content?.forward?.text, message?.text.isEmpty == true { chat.preview = forwarded }
            if let message { chat.updatedAt = message.timestamp }
            chat.lastMessageAt = message?.timestamp.unixMillis ?? 0
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
    /// и счётчик не трогается. Сравнение идёт со временем сообщения, а не события чата:
    /// правка или реакция после него не должны оставлять бейдж. `setAsUnread` — чат помечен
    /// непрочитанным вручную.
    public func applyOwnRead(chatId: String, mark: Int64, setAsUnread: Bool) throws(MaxlyError) {
        if setAsUnread {
            readMarkBook.forget(chatId)
        } else if mark > 0 {
            readMarkBook.notePush(mark, chatId: chatId)
        }
        do {
            guard let chat = try chat(id: chatId) else { return }
            if setAsUnread {
                guard chat.unreadCount == 0 else { return }
                chat.unreadCount = 1
            } else {
                let readTime = ReadMarks.readTime(lastMessageAt: chat.lastMessageAt, updatedAt: chat.updatedAt)
                guard mark > 0, mark >= readTime, chat.unreadCount != 0 else { return }
                chat.unreadCount = 0
            }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    private func reportPeerRead(_ marks: [(String, Int64)]) {
        guard let peerReadHandler, !marks.isEmpty else { return }
        Task {
            for (chatId, mark) in marks { await peerReadHandler(chatId, mark) }
        }
    }

    /// Собеседник прочитал сообщения до `mark` (мс): свои сообщения до этого времени прочитаны.
    public func applyPeerRead(chatId: String, mark: Int64) throws(MaxlyError) {
        do {
            guard mark > 0, let chat = try chat(id: chatId), mark > chat.peerReadMark else { return }
            chat.peerReadMark = mark
            try modelContext.save()
            reportPeerRead([(chatId, mark)])
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Сервер принял своё сообщение. Если строка показывает именно его (по локальному id),
    /// у неё появляются серверный id и галочка, даже когда время сервера чуть раньше
    /// времени телефона. Иначе это обычное новое сообщение.
    public func noteSent(chatId: String, localId: String, serverId: String?, preview: String, at: Date, authorId: String?) throws(MaxlyError) {
        do {
            guard let chat = try chat(id: chatId) else { return }
            guard chat.lastLocalId == localId else {
                _ = try noteMessage(
                    chatId: chatId, messageId: serverId, preview: preview, at: at, incoming: false,
                    authorId: authorId, outgoing: true, delivery: .sent
                )
                return
            }
            if let serverId { chat.lastMessageId = serverId }
            chat.lastDeliveryRaw = DeliveryState.sent.rawValue
            chat.lastLocalId = nil
            // Время сервера, а не телефона: с ним собеседник ставит отметку прочтения.
            chat.lastMessageAt = at.unixMillis
            if at > chat.updatedAt { chat.updatedAt = at }
            try modelContext.save()
        } catch let error as MaxlyError {
            throw error
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Своё сообщение не ушло: строка показывает ошибку вместо галочек, если оно последнее.
    public func noteSendFailed(chatId: String, localId: String) throws(MaxlyError) {
        do {
            guard let chat = try chat(id: chatId), chat.lastOutgoing, chat.lastLocalId == localId else { return }
            chat.lastDeliveryRaw = DeliveryState.failed.rawValue
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Публичные чаты и каналы на сервере. Пустой запрос сервер не спрашивает.
    public nonisolated func search(query: String) async throws(MaxlyError) -> [ChatSearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        switch await api.searchPublic(query: term) {
        case .success(let results):
            return results
        case .failure(let error):
            Log.warning(.chats, "Поиск на сервере не удался: \(error)")
            throw error.maxlyError
        }
    }

    public nonisolated func searchMessages(query: String) async throws(MaxlyError) -> [FoundMessage] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        switch await api.searchMessages(query: term) {
        case .success(let found):
            // Одно сообщение — одна строка, даже если сервер повторил его.
            var seen = Set<String>()
            return found.filter { seen.insert("\($0.chatId)/\($0.messageId)").inserted }
        case .failure(let error):
            Log.warning(.chats, "Поиск сообщений не удался: \(error)")
            throw error.maxlyError
        }
    }

    /// Звук чата: сначала база (кнопка и строка списка меняются сразу), затем сервер. Сервер
    /// не принял — строка возвращается как была. Раньше база ждала ответа: кнопка звука в
    /// канале срабатывала с задержкой, а при переподключении — будто не срабатывала вовсе.
    public func setMuted(_ muted: Bool, chatId: String) async throws(MaxlyError) {
        let previous: Bool
        muteToggles[chatId] = Date()
        // Ответ сервера тоже отметка: список, запрошенный до него, мог посчитаться по старому конфигу.
        defer { muteToggles[chatId] = Date() }
        do {
            guard let chat = try chat(id: chatId) else { throw MaxlyError.invalidRequest }
            previous = chat.isMuted
            chat.isMuted = muted
            try modelContext.save()
        } catch let error as MaxlyError {
            throw error
        } catch {
            throw .storageError
        }
        notify()
        if case .failure(let error) = await api.setChatMuted(chatId: chatId, muted: muted) {
            Log.warning(.chats, "Уведомления чата не изменены: \(error)")
            // Откат, только если строку за это время не переключили снова.
            if let chat = try? chat(id: chatId), chat.isMuted == muted {
                chat.isMuted = previous
                try? modelContext.save()
                notify()
            }
            throw error.maxlyError
        }
    }

    /// Звук чата из ядра (событие `chatMute`): `1` без звука, `0` со звуком, `-1` неизвестно —
    /// строка не трогается. `untilMs` — сырой `dontDisturbUntil`: срок в будущем включит звук по
    /// таймеру. Событие свежее любого ответа списка, запрошенного до него (см. `muteToggles`).
    public func applyMute(chatId: String, muted: Int, untilMs: Int64) {
        guard muted == 0 || muted == 1, !chatId.isEmpty else { return }
        muteToggles[chatId] = Date()
        scheduleMuteExpiry(chatId: chatId, muted: muted, untilMs: untilMs)
        guard let chat = try? chat(id: chatId), chat.isMuted != (muted == 1) else { return }
        chat.isMuted = muted == 1
        try? modelContext.save()
        notify()
    }

    /// Событие `config`: конфиг аккаунта стал известен, звук известных чатов перечитывается из ядра.
    public func reloadMutes() async {
        guard let ids = try? modelContext.fetch(FetchDescriptor<SDChat>()).map(\.id) else { return }
        for id in ids {
            let state = await api.chatMute(chatId: id)
            applyMute(chatId: id, muted: state.muted, untilMs: state.untilMs)
        }
    }

    private func scheduleMuteExpiry(chatId: String, muted: Int, untilMs: Int64) {
        if let known = muteExpiries[chatId] {
            if muted == 1, known.until == untilMs { return }
            known.task.cancel()
            muteExpiries[chatId] = nil
        }
        guard muted == 1, untilMs > 0 else { return }
        let delay = Double(untilMs) / 1000 - clock().timeIntervalSince1970
        let task = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await self?.expireMute(chatId: chatId, untilMs: untilMs)
        }
        muteExpiries[chatId] = (untilMs, task)
    }

    /// Срок вышел: ядро считает звук по своим часам; не знает — звук включается.
    private func expireMute(chatId: String, untilMs: Int64) async {
        guard muteExpiries[chatId]?.until == untilMs else { return }
        muteExpiries[chatId] = nil
        let state = await api.chatMute(chatId: chatId)
        guard muteExpiries[chatId] == nil else { return }
        if state.muted == 1, state.untilMs != untilMs {
            applyMute(chatId: chatId, muted: 1, untilMs: state.untilMs)
        } else {
            applyMute(chatId: chatId, muted: 0, untilMs: 0)
        }
    }

    /// Записи с сервера без звука для чатов, переключённых после `requestedAt` (см. `muteToggles`).
    private func keepingLocalMute(_ records: [ChatRecord], requestedAt: Date) -> [ChatRecord] {
        guard !muteToggles.isEmpty else { return records }
        return records.map { record in
            guard let toggled = muteToggles[record.id], toggled >= requestedAt else { return record }
            var kept = record
            kept.isMuted = nil
            return kept
        }
    }

    // MARK: Закреплённые (сервер) и пометки (на устройстве)

    /// Закреплённые чаты с сервера сверху вниз: вход, свой запрос или пуш с другого устройства.
    /// Список заменяет локальное закрепление целиком: чаты не из списка откреплены.
    public func applyServerPins(_ chatIds: [String]) throws(MaxlyError) {
        var seen = Set<String>()
        let ids = chatIds.filter { !$0.isEmpty && seen.insert($0).inserted }
        serverPins = ids
        do {
            let pinned = try modelContext.fetch(FetchDescriptor<SDChat>(predicate: #Predicate { $0.pinOrder != nil }))
            let listed = try chats(ids: ids)
            var changed = false
            for chat in pinned where !seen.contains(chat.id) {
                chat.pinOrder = nil
                changed = true
            }
            for (index, id) in ids.enumerated() {
                guard let chat = listed[id], chat.pinOrder != index else { continue }
                chat.pinOrder = index
                changed = true
            }
            guard changed else { return }
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Закрепить или открепить. Новый закреплённый встаёт первым. На сервер уходит весь новый
    /// список; база меняется только после ответа сервера, так что при ошибке всё остаётся как было,
    /// а экран откатывает своё оптимистичное изменение.
    public func setPinned(_ pinned: Bool, chatId: String) async throws(MaxlyError) {
        let current: [String]
        do {
            guard try chat(id: chatId) != nil else { throw MaxlyError.invalidRequest }
            current = try currentPins()
        } catch let error as MaxlyError {
            throw error
        } catch {
            throw .storageError
        }
        if pinned {
            guard !current.contains(chatId) else { return }
            try await sendPins([chatId] + current)
        } else {
            guard current.contains(chatId) else { return }
            try await sendPins(current.filter { $0 != chatId })
        }
    }

    /// Новый порядок закреплённых сверху вниз. Закреплённые, которых нет в `chatIds` (архив или
    /// ещё не загруженные строки), остаются в списке сервера после них в прежнем порядке.
    public func reorderPinned(_ chatIds: [String]) async throws(MaxlyError) {
        let current: [String]
        do {
            current = try currentPins()
        } catch {
            throw .storageError
        }
        let moved = chatIds.filter { current.contains($0) }
        let next = moved + current.filter { !moved.contains($0) }
        guard next != current else { return }
        try await sendPins(next)
    }

    /// Список, от которого строится следующее действие: неподтверждённый запрос, список сервера,
    /// а если сервер ещё не прислал его — закреплённые строки базы.
    private func currentPins() throws -> [String] {
        if let requestedPins { return requestedPins }
        if let serverPins { return serverPins }
        let rows = try modelContext.fetch(FetchDescriptor<SDChat>(predicate: #Predicate { $0.pinOrder != nil }))
        return rows.sorted { ($0.pinOrder ?? 0, $0.id) < ($1.pinOrder ?? 0, $1.id) }.map(\.id)
    }

    private func sendPins(_ ids: [String]) async throws(MaxlyError) {
        let started = generation
        pinRequests += 1
        let request = pinRequests
        requestedPins = ids
        let result = await api.setPinnedChats(ids)
        if request == pinRequests { requestedPins = nil }
        switch result {
        case .success(let confirmed):
            try ensureCurrent(started)
            // Ответ на более ранний запрос не перетирает более поздний: его применит свой ответ
            // или поток закреплённых из ядра.
            guard request == pinRequests else { return }
            try applyServerPins(confirmed)
        case .failure(let error):
            Log.warning(.chats, "Закреплённые не сохранены на сервере: \(error)")
            throw error.maxlyError
        }
    }

    public func setMarkedUnread(_ unread: Bool, chatId: String) async throws(MaxlyError) {
        do {
            guard let chat = try chat(id: chatId), chat.isMarkedUnread != unread else { return }
            chat.isMarkedUnread = unread
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    // MARK: Черновики

    public func draft(chatId: String) async -> String? {
        (try? chat(id: chatId))?.draftText
    }

    public func draftTime(chatId: String) async -> Date? {
        (try? chat(id: chatId))?.draftAt
    }

    /// Пустой текст удаляет черновик. Чата ещё нет в базе — черновик не сохраняется.
    public func saveDraft(_ text: String, chatId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chat = try? chat(id: chatId), (chat.draftText ?? "") != trimmed else { return }
        chat.draftText = trimmed.isEmpty ? nil : trimmed
        chat.draftAt = trimmed.isEmpty ? nil : clock()
        guard (try? modelContext.save()) != nil else { return }
        notify()
    }

    // MARK: Набор текста

    /// Серверные папки (`FOLDERS_GET` при входе, `NOTIF_FOLDERS` и свои изменения).
    public nonisolated func folders() -> AsyncStream<[ChatFolder]> {
        api.folderUpdates()
    }

    public nonisolated func typing() -> AsyncStream<[String: [TypingActivity]]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addTypingObserver(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeTypingObserver(id) }
            }
        }
    }

    /// Пуш «печатает» от `userId`. Повторный пуш продлевает срок и заменяет тип.
    /// `type` — значение `type` пуша 129, `nil` — его нет (это обычный набор текста).
    public func noteTyping(chatId: String, userId: String, type: String? = nil) {
        guard !chatId.isEmpty, !userId.isEmpty else { return }
        typingTracker.note(chatId: chatId, userId: userId, type: type, at: clock())
        if typingNames[userId] == nil, let name = knownName(userId: userId) {
            typingNames[userId] = name
        }
        publishTyping()
        scheduleTypingExpiry()
    }

    /// Сообщение от пользователя: он больше не печатает.
    public func stopTyping(chatId: String, userId: String) {
        guard typingTracker.stop(chatId: chatId, userId: userId) else { return }
        publishTyping()
    }

    /// Снимает истёкшие отметки. Вызывается таймером и тестами.
    func expireTyping() {
        if typingTracker.expire(at: clock()) { publishTyping() }
    }

    /// Последнее известное имя автора: из сохранённых сообщений в любом чате.
    private func knownName(userId: String) -> String? {
        let id = userId
        var descriptor = FetchDescriptor<SDMessage>(
            predicate: #Predicate { $0.authorId == id && $0.authorName != "" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let name = (try? modelContext.fetch(descriptor).first?.authorName) ?? ""
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func scheduleTypingExpiry() {
        guard typingExpiry == nil else { return }
        typingExpiry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, await self.tickTyping() else { return }
            }
        }
    }

    /// `false`, когда печатающих не осталось и таймер можно остановить.
    private func tickTyping() -> Bool {
        expireTyping()
        if typingTracker.isEmpty {
            typingExpiry = nil
            return false
        }
        return true
    }

    private func typingSnapshot() -> [String: [TypingActivity]] {
        var result: [String: [TypingActivity]] = [:]
        for (chatId, list) in typingTracker.snapshot(at: clock()) {
            var named: [TypingActivity] = []
            for var activity in list {
                activity.name = typingNames[activity.userId]
                named.append(activity)
            }
            result[chatId] = named
        }
        return result
    }

    private func publishTyping() {
        let value = typingSnapshot()
        for continuation in typingObservers.values {
            continuation.yield(value)
        }
    }

    private func addTypingObserver(_ id: UUID, _ continuation: AsyncStream<[String: [TypingActivity]]>.Continuation) {
        if case .terminated = continuation.yield(typingSnapshot()) { return }
        typingObservers[id] = continuation
    }

    private func removeTypingObserver(_ id: UUID) {
        typingObservers[id] = nil
    }

    private struct ReadMark {
        let messageId: String?
        /// Серверное время этого сообщения, мс. `0` — неизвестно, его найдёт ядро.
        let time: Int64
    }

    /// Отметка для сервера, если было что читать. Иначе `nil`.
    private func markReadLocally(chatId: String) throws(MaxlyError) -> ReadMark? {
        do {
            guard let chat = try chat(id: chatId), chat.unreadCount > 0 else { return nil }
            let mark = ReadMark(messageId: chat.lastMessageId, time: chat.lastMessageAt)
            chat.unreadCount = 0
            try modelContext.save()
            notify()
            return mark
        } catch {
            throw .storageError
        }
    }

    /// База не очищалась с начала запроса. Иначе ответ устарел, и вызов считается отменённым.
    private func ensureCurrent(_ started: Int) throws(MaxlyError) {
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

    static func domain(_ chat: SDChat) -> Chat {
        var last: ChatLastMessage?
        let media = chat.lastMediaRaw.flatMap(MessageMediaKind.init(rawValue:))
        if chat.lastOutgoing || chat.lastAuthorId != nil || media != nil {
            var delivery = chat.lastOutgoing ? DeliveryState(rawValue: chat.lastDeliveryRaw ?? "") ?? .sent : nil
            // Собеседник прочитал всё до своей отметки: отправленное раньше неё прочитано.
            // Отметка — самая свежая из карточки чата и пуша прочтения (`peerReadMark` только
            // растёт). Сравнение — со временем своего сообщения: правка или реакция после него
            // двигают время чата, и галочки не становились двойными.
            let sentAt = ReadMarks.readTime(lastMessageAt: chat.lastMessageAt, updatedAt: chat.updatedAt)
            if delivery == .sent, ReadMarks.isReadByPeer(peerMark: chat.peerReadMark, messageTime: sentAt) {
                delivery = .read
            }
            last = ChatLastMessage(
                authorId: chat.lastAuthorId,
                authorName: chat.lastAuthorName,
                isOutgoing: chat.lastOutgoing,
                delivery: delivery,
                media: media,
                thumbnailURL: chat.lastThumbnailURLString.flatMap(URL.init(string:)),
                isForwarded: chat.lastForwarded
            )
        }
        let draft: ChatDraft? = chat.draftText.flatMap { text in
            text.isEmpty ? nil : ChatDraft(text: text, updatedAt: chat.draftAt ?? chat.updatedAt)
        }
        return Chat(
            id: chat.id,
            title: chat.title,
            type: chat.type,
            lastMessageId: chat.lastMessageId,
            unreadCount: chat.unreadCount,
            updatedAt: chat.updatedAt,
            preview: chat.preview,
            lastMessage: last,
            avatarURL: chat.avatarURLString.flatMap(URL.init(string:)),
            pinOrder: chat.pinOrder,
            isMuted: chat.isMuted,
            isMarkedUnread: chat.isMarkedUnread,
            isArchived: chat.isArchived,
            isBot: chat.isBot,
            isVerified: chat.isVerified,
            draft: draft,
            commentsEnabled: chat.commentsOption < 0 ? nil : chat.commentsOption == 1,
            canWrite: chat.canWriteOption < 0 ? nil : chat.canWriteOption == 1,
            hasWebApp: chat.hasWebApp
        )
    }
}
