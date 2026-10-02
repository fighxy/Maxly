import Foundation
import SwiftData
import OrbitleDomain

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
    private var typingObservers: [UUID: AsyncStream<[String: [String]]>.Continuation] = [:]
    /// Кто печатает: id чата → id пользователя → когда это перестанет быть правдой.
    private var typingUntil: [String: [String: Date]] = [:]
    private var typingExpiry: Task<Void, Never>?
    private let typingTTL: TimeInterval
    private let clock: @Sendable () -> Date
    private nonisolated let api: any MaxAPI
    /// Растёт при каждой очистке базы. Ответ сервера на запрос, начатый до очистки
    /// (например, до выхода), в базу уже не пишется.
    private var generation = 0
    /// Диалоги, открытые из контактов, которых ещё нет в базе: id чата → черновик.
    private var pendingDialogs: [String: DialogDraft] = [:]

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

    /// `typingTTL` — сколько держать «печатает…» без повторного пуша.
    public init(
        modelContainer: ModelContainer,
        api: any MaxAPI,
        typingTTL: TimeInterval = 6,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
        self.typingTTL = typingTTL
        self.clock = clock
        self.capabilities = [.pin, .reorderPins, .markUnread, .mute, .serverSearch]
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
    public func refresh() async throws(OrbitleError) {
        let started = generation
        switch await api.fetchChats() {
        case .success(let records):
            try ensureCurrent(started)
            try upsert(records)
        case .failure(let error):
            throw error.orbitleError
        }
    }

    /// Один чат с сервера (`CHAT_INFO`).
    public func refresh(chatId: String) async throws(OrbitleError) {
        let started = generation
        switch await api.fetchChat(id: chatId) {
        case .success(let record):
            try ensureCurrent(started)
            try upsert([record])
        case .failure(let error):
            throw error.orbitleError
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

    public func upsert(_ records: [ChatRecord]) throws(OrbitleError) {
        var raised: [(String, Int64)] = []
        do {
            // Одна выборка на весь пакет, а не по запросу на каждую запись.
            var existing = try chats(ids: records.map(\.id))
            defer { reportPeerRead(raised) }
            for record in records {
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
            } else {
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
        if let verified = record.isVerified { chat.isVerified = verified }
        if let comments = record.commentsEnabled { chat.commentsOption = comments ? 1 : 0 }
        if let canWrite = record.canWrite { chat.canWriteOption = canWrite ? 1 : 0 }
        if record.pinsKnown { chat.pinOrder = record.pinOrder }
    }

    /// Удаляет чат вместе с сообщениями. Сообщения без связи с чатом (записанные раньше
    /// самого чата) каскад не видит, поэтому они удаляются по `chatId` явно.
    public func delete(chatId: String) throws(OrbitleError) {
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
    public func removeAll() throws(OrbitleError) {
        generation += 1
        serverPins = nil
        requestedPins = nil
        pendingDialogs.removeAll()
        typingUntil.removeAll()
        publishTyping()
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
    public func markAsRead(chatId: String) async throws(OrbitleError) {
        guard let mark = try markReadLocally(chatId: chatId) else { return }
        if case .failure(let error) = await api.markRead(chatId: chatId, messageId: mark.messageId) {
            throw error.orbitleError
        }
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
    ) throws(OrbitleError) -> Bool {
        do {
            guard let chat = try chat(id: chatId) ?? insertPendingDialog(chatId: chatId, at: at) else { return false }
            if at >= chat.updatedAt {
                if let messageId { chat.lastMessageId = messageId }
                chat.preview = preview
                chat.updatedAt = at
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
    public func noteEdit(chatId: String, messageId: String, text: String) throws(OrbitleError) {
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
    public func replaceLast(chatId: String, with message: MessageRecord?, currentUser: String = "") throws(OrbitleError) {
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
    public func applyOwnRead(chatId: String, mark: Int64, setAsUnread: Bool) throws(OrbitleError) {
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

    private func reportPeerRead(_ marks: [(String, Int64)]) {
        guard let peerReadHandler, !marks.isEmpty else { return }
        Task {
            for (chatId, mark) in marks { await peerReadHandler(chatId, mark) }
        }
    }

    /// Собеседник прочитал сообщения до `mark` (мс): свои сообщения до этого времени прочитаны.
    public func applyPeerRead(chatId: String, mark: Int64) throws(OrbitleError) {
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
    public func noteSent(chatId: String, localId: String, serverId: String?, preview: String, at: Date, authorId: String?) throws(OrbitleError) {
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
            if at > chat.updatedAt { chat.updatedAt = at }
            try modelContext.save()
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw .storageError
        }
        notify()
    }

    /// Своё сообщение не ушло: строка показывает ошибку вместо галочек, если оно последнее.
    public func noteSendFailed(chatId: String, localId: String) throws(OrbitleError) {
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
    public nonisolated func search(query: String) async throws(OrbitleError) -> [ChatSearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        switch await api.searchPublic(query: term) {
        case .success(let results):
            return results
        case .failure(let error):
            Log.warning(.chats, "Поиск на сервере не удался: \(error)")
            throw error.orbitleError
        }
    }

    public nonisolated func searchMessages(query: String) async throws(OrbitleError) -> [FoundMessage] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        switch await api.searchMessages(query: term) {
        case .success(let found):
            // Одно сообщение — одна строка, даже если сервер повторил его.
            var seen = Set<String>()
            return found.filter { seen.insert("\($0.chatId)/\($0.messageId)").inserted }
        case .failure(let error):
            Log.warning(.chats, "Поиск сообщений не удался: \(error)")
            throw error.orbitleError
        }
    }

    /// Звук чата: сначала сервер, затем база. При ошибке строка остаётся как была.
    public func setMuted(_ muted: Bool, chatId: String) async throws(OrbitleError) {
        do {
            guard try chat(id: chatId) != nil else { throw OrbitleError.invalidRequest }
        } catch let error as OrbitleError {
            throw error
        } catch {
            throw .storageError
        }
        if case .failure(let error) = await api.setChatMuted(chatId: chatId, muted: muted) {
            Log.warning(.chats, "Уведомления чата не изменены: \(error)")
            throw error.orbitleError
        }
        do {
            guard let chat = try chat(id: chatId) else { return }
            chat.isMuted = muted
            try modelContext.save()
        } catch {
            throw .storageError
        }
        notify()
    }

    // MARK: Закреплённые (сервер) и пометки (на устройстве)

    /// Закреплённые чаты с сервера сверху вниз: вход, свой запрос или пуш с другого устройства.
    /// Список заменяет локальное закрепление целиком: чаты не из списка откреплены.
    public func applyServerPins(_ chatIds: [String]) throws(OrbitleError) {
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
    public func setPinned(_ pinned: Bool, chatId: String) async throws(OrbitleError) {
        let current: [String]
        do {
            guard try chat(id: chatId) != nil else { throw OrbitleError.invalidRequest }
            current = try currentPins()
        } catch let error as OrbitleError {
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
    public func reorderPinned(_ chatIds: [String]) async throws(OrbitleError) {
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

    private func sendPins(_ ids: [String]) async throws(OrbitleError) {
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
            throw error.orbitleError
        }
    }

    public func setMarkedUnread(_ unread: Bool, chatId: String) async throws(OrbitleError) {
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

    public nonisolated func typing() -> AsyncStream<[String: [String]]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addTypingObserver(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeTypingObserver(id) }
            }
        }
    }

    /// Пуш «печатает» от `userId`. Повторный пуш продлевает срок.
    public func noteTyping(chatId: String, userId: String) {
        guard !chatId.isEmpty, !userId.isEmpty else { return }
        typingUntil[chatId, default: [:]][userId] = clock().addingTimeInterval(typingTTL)
        publishTyping()
        scheduleTypingExpiry()
    }

    /// Сообщение от пользователя: он больше не печатает.
    public func stopTyping(chatId: String, userId: String) {
        guard typingUntil[chatId]?[userId] != nil else { return }
        typingUntil[chatId]?[userId] = nil
        if typingUntil[chatId]?.isEmpty == true { typingUntil[chatId] = nil }
        publishTyping()
    }

    /// Снимает истёкшие отметки. Вызывается таймером и тестами.
    func expireTyping() {
        let now = clock()
        var changed = false
        for (chatId, users) in typingUntil {
            let alive = users.filter { $0.value > now }
            if alive.count != users.count {
                changed = true
                typingUntil[chatId] = alive.isEmpty ? nil : alive
            }
        }
        if changed { publishTyping() }
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
        if typingUntil.isEmpty {
            typingExpiry = nil
            return false
        }
        return true
    }

    private func typingSnapshot() -> [String: [String]] {
        typingUntil.mapValues { $0.keys.sorted() }
    }

    private func publishTyping() {
        let value = typingSnapshot()
        for continuation in typingObservers.values {
            continuation.yield(value)
        }
    }

    private func addTypingObserver(_ id: UUID, _ continuation: AsyncStream<[String: [String]]>.Continuation) {
        if case .terminated = continuation.yield(typingSnapshot()) { return }
        typingObservers[id] = continuation
    }

    private func removeTypingObserver(_ id: UUID) {
        typingObservers[id] = nil
    }

    private struct ReadMark {
        let messageId: String?
    }

    /// Отметка для сервера, если было что читать. Иначе `nil`.
    private func markReadLocally(chatId: String) throws(OrbitleError) -> ReadMark? {
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
    private func ensureCurrent(_ started: Int) throws(OrbitleError) {
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
            if delivery == .sent, chat.peerReadMark > 0, chat.peerReadMark >= chat.updatedAt.unixMillis {
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
            canWrite: chat.canWriteOption < 0 ? nil : chat.canWriteOption == 1
        )
    }
}
