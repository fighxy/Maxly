import Foundation
import OrbitleDomain

/// Ошибки серверных вызовов.
public enum MaxAPIError: Error, Sendable, Equatable {
    /// Нет сети или соединение с сервером потеряно.
    case offline
    /// Сервер вернул ошибку с кодом. `text` — фраза сервера для экрана, если она есть.
    case server(code: String, text: String?)
    /// Сохранённый токен больше не действует.
    case sessionExpired
    /// Ввод отклонён, например неверный пароль.
    case rejected(String)
    /// Запрос неверен или объект не найден.
    case invalidResponse
    /// Вызов отменён (задача отменена, ядро закрыто или ответ пришёл на устаревший запрос).
    case cancelled
    /// Ошибка без категории (сбой ядра, неверный аргумент).
    case unknown

    /// Имеет ли смысл повторить запрос позже.
    public var isRetryable: Bool {
        switch self {
        case .offline, .server: true
        case .invalidResponse, .sessionExpired, .rejected, .cancelled, .unknown: false
        }
    }

    /// Категория ошибки для UI (architecture.md, «Ошибки и офлайн»).
    public var orbitleError: OrbitleError {
        switch self {
        case .offline: .networkUnavailable
        case .server(let code, let text): .server(code: code, text: text)
        case .sessionExpired: .authExpired
        case .rejected(let message): .rejected(message)
        case .invalidResponse: .invalidRequest
        case .cancelled: .cancelled
        case .unknown: .unknown
        }
    }
}

/// Ответ сервера на отправку сообщения.
public struct SentMessage: Sendable, Hashable {
    public var serverId: String
    public var timestamp: Date

    public init(serverId: String, timestamp: Date) {
        self.serverId = serverId
        self.timestamp = timestamp
    }
}

/// Серверные вызовы, которые нужны репозиториям. Протокол, чтобы в тестах
/// подставлять фейковую реализацию.
public protocol MaxAPI: Sendable {
    func fetchChats() async -> Result<[ChatRecord], MaxAPIError>
    /// Новые адреса просроченных фото. Пустой ответ — обновлять нечего.
    func refreshPhotoURLs(_ items: [PhotoRefreshKey]) async -> Result<[RefreshedPhotoURL], MaxAPIError>
    /// Список чатов и признак, что он полный (весь список аккаунта, первый после входа).
    func fetchChatList() async -> Result<ChatListPage, MaxAPIError>
    /// Один чат. Ошибка, если сервер его не вернул.
    func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError>
    /// Сообщения чата строго старше `before` (самые новые, если `nil`), не больше `limit`.
    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// Свежая страница открытого пользователем чата: уходит и во время паузы чтений.
    func fetchOpenedMessages(chatId: String, limit: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// Страница строго старше `before`, когда пользователь листает вверх: уходит и во время паузы чтений.
    func fetchOlderMessages(chatId: String, before: Date, limit: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// Сплошная страница вокруг сообщения `messageId` (или момента `at`, если он задан): до
    /// `forward` новее и до `backward` старше, от старых к новым.
    func fetchMessagesAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// Сообщения с вложениями `types` вокруг `anchorId`: до `forward` новее, до `backward` старше.
    func fetchSharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError>
    /// `clientId` это локальный id. Ядро само ставит числовой `cid` в пакет, локальный id на сервер не уходит.
    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError>
    /// Ответ на сообщение `replyTo` (серверный id). `nil` — обычное сообщение.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError>
    /// Текст с анимодзи (`ANIMOJI` поверх эмодзи). Без отметок — как обычный текст.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, animoji: [CoreAnimojiMark]) async -> Result<SentMessage, MaxAPIError>
    /// Текст с анимодзи и упоминаниями.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, animoji: [CoreAnimojiMark], mentions: [CoreMentionMark]) async -> Result<SentMessage, MaxAPIError>
    /// Текст с любой разметкой поля ввода (жирный, курсив, ссылки, анимодзи, упоминания).
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, formatting: [TextSpan]) async -> Result<SentMessage, MaxAPIError>
    /// Заменить текст отправленного сообщения (по серверному id).
    func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError>
    /// Заменить текст и всю разметку (пустой список снимает её).
    func editMessage(chatId: String, messageId: String, text: String, formatting: [TextSpan]) async -> Result<MessageRecord, MaxAPIError>
    /// Удалить выбранное одним запросом: какие id сервер удалил, какие нет.
    func deleteSelection(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<CoreDeleteResult, MaxAPIError>
    /// Диалог удаления по серверным id (`deletePlan` ядра); `nil` — источник не умеет.
    func deletePlan(chatId: String, messageIds: [String]) async -> CoreDeletePlan?
    /// `edit-timeout` сервера в секундах; `0` — неизвестно.
    func editTimeoutSeconds() async -> Int64
    /// Свои права в чате; `nil` — источник не знает.
    func chatRights(chatId: String) async -> CoreChatRights?
    /// Удалить сообщения по серверным id: у себя или у всех.
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError>
    /// Переслать сообщение. Ответ — новое сообщение в целевом чате.
    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError>
    /// `messageId` nil значит, что локально нечего отмечать: сервер не вызывается.
    func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError>
    /// Отметка временем прочитанного сообщения `mark` (мс, серверное). Ответ — отметка и
    /// счётчик сервера, `nil` — сервер не вызывался или источник ответа не знает.
    func markRead(chatId: String, messageId: String?, at mark: Int64) async -> Result<CoreReadMark?, MaxAPIError>
    /// Чат непрочитан начиная с сообщения в `date`. Ответ — число непрочитанных на сервере.
    func markUnread(chatId: String, from date: Date) async -> Result<Int, MaxAPIError>
    /// Закреплённые чаты целиком, сверху вниз. Ответ — список, который подтвердил сервер.
    func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError>
    /// Выключить уведомления чата насовсем или включить обратно.
    func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError>
    /// Звук чата по конфигу ядра, без запроса (перечитать после события `config`, по концу
    /// временного выключения).
    func chatMute(chatId: String) async -> ChatMuteState
    /// Серверные папки для полосы над списком, без «Все»: сразу, если известны, и после
    /// каждого изменения. Пустой массив — папок нет.
    func folderUpdates() -> AsyncStream<[ChatFolder]>
    /// Поставить свою реакцию `emoji` на сообщение (серверный id) или снять её (`nil`).
    /// Непустой `postId` — комментарий этого поста. Ответ — реакции, если сервер их прислал.
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError>
    /// Реакции сообщений по серверным id. Сообщения, о которых сервер промолчал, пропущены.
    func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError>
    /// Кто поставил реакции на сообщение.
    func reactionUsers(chatId: String, messageId: String) async -> Result<[ReactionUser], MaxAPIError>
    /// «Кем прочитано» сообщения (серверные id): отреагировавшие, затем прочитавшие.
    func messageReaders(chatId: String, messageId: String) async -> Result<[MessageReader], MaxAPIError>
    /// Есть ли в чате «Кем прочитано», без запроса.
    func readersAvailable(chatId: String) -> Bool
    /// Расшифровка голосового: `messageId` серверный, `audioId` — id вложения.
    func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError>
    /// Эмодзи каталога реакций сервера.
    func reactionCatalog() async -> Result<[String], MaxAPIError>
    /// Загрузить вложения и отправить одним сообщением с подписью. Контакт уходит один,
    /// без подписи. `replyTo` — серверный id цитаты. Отмена задачи отменяет загрузку.
    func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                         progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError>
    /// Публичные чаты и каналы на сервере по названию или ссылке.
    func searchPublic(query: String) async -> Result<[ChatSearchResult], MaxAPIError>
    /// Сообщения во всех чатах по тексту.
    func searchMessages(query: String) async -> Result<[FoundMessage], MaxAPIError>
    /// Новая группа. `nil` в успехе — сервер не вернул чат.
    func createGroup(title: String, memberIds: [String]) async -> Result<ChatRecord?, MaxAPIError>
    /// Новый канал. `nil` в успехе — сервер не вернул чат.
    func createChannel(title: String) async -> Result<ChatRecord?, MaxAPIError>
    /// Вход по ссылке приглашения.
    func joinByLink(_ link: String) async -> Result<ChatRecord?, MaxAPIError>
    /// Удалить чат (`CHAT_DELETE` 52). `lastEventTimeMs` — время последнего события чата.
    func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError>
    /// Выйти из группы или отписаться от канала (`CHAT_LEAVE` 58).
    func leaveChat(chatId: String) async -> Result<Void, MaxAPIError>
    /// Очистить переписку (`CHAT_CLEAR` 54). Те же три поля, что у удаления чата.
    func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError>
    func pinMessage(chatId: String, messageId: String) async -> Result<Void, MaxAPIError>
    /// Закрепы чата (`241`), от новых к старым.
    func pinnedMessages(chatId: String) async -> Result<[ChatPin], MaxAPIError>
    /// `pin` / `unpin` / `unpinAll` (`242`).
    func updatePinned(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async -> Result<Void, MaxAPIError>
    func scheduleMessage(chatId: String, text: String, sendAtMs: Int64) async -> Result<Void, MaxAPIError>
    func scheduledMessages(chatId: String) async -> Result<[FoundMessage], MaxAPIError>
    func sendPoll(chatId: String, title: String, answers: [String]) async -> Result<Void, MaxAPIError>
    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async -> Result<Void, MaxAPIError>
    func castPollVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async -> Result<CorePollCounts, MaxAPIError>
    func pollUpdates(chatId: String, polls: [CorePollRef]) async -> Result<[CorePollCounts], MaxAPIError>
    func editScheduled(chatId: String, messageId: String, text: String, sendAtMs: Int64) async -> Result<FoundMessage, MaxAPIError>
    func cancelScheduled(chatId: String, messageIds: [String]) async -> Result<Void, MaxAPIError>
    func searchInChat(chatId: String, query: String) async -> Result<[FoundMessage], MaxAPIError>
    func chatMembers(chatId: String) async -> Result<[CoreChatMember], MaxAPIError>
    func botCommands(botId: String) async -> Result<[CoreBotCommand], MaxAPIError>
    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String?) async -> Result<CoreButtonAnswer, MaxAPIError>
}

/// Ответ списка чатов. `complete` — это весь список аккаунта: чатов, которых в нём нет,
/// аккаунт больше не видит (покинул на другом устройстве).
public struct ChatListPage: Sendable {
    public var records: [ChatRecord]
    public var complete: Bool

    public init(records: [ChatRecord], complete: Bool) {
        self.records = records
        self.complete = complete
    }
}

public extension MaxAPI {
    /// Источник без обновления адресов: просроченное фото остаётся как есть.
    func refreshPhotoURLs(_ items: [PhotoRefreshKey]) async -> Result<[RefreshedPhotoURL], MaxAPIError> {
        .success([])
    }

    func fetchChatList() async -> Result<ChatListPage, MaxAPIError> {
        await fetchChats().map { ChatListPage(records: $0, complete: false) }
    }

    func fetchOpenedMessages(chatId: String, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await fetchMessages(chatId: chatId, before: nil, limit: limit)
    }
    func fetchOlderMessages(chatId: String, before: Date, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await fetchMessages(chatId: chatId, before: before, limit: limit)
    }
    /// Источник без страниц вокруг сообщения: переход к далёкому сообщению недоступен.
    func fetchMessagesAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без серверных общих медиа: профиль обходится историей из кэша.
    func fetchSharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без серверных закреплённых: запрос отклоняется.
    func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError> { .failure(.invalidResponse) }
    func markUnread(chatId: String, from date: Date) async -> Result<Int, MaxAPIError> { .failure(.invalidResponse) }
    /// Источник без ответа на отметку: прежний вызов, ответа нет.
    func markRead(chatId: String, messageId: String?, at mark: Int64) async -> Result<CoreReadMark?, MaxAPIError> {
        await markRead(chatId: chatId, messageId: messageId).map { _ -> CoreReadMark? in nil }
    }
    func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func chatMute(chatId: String) async -> ChatMuteState { .unknown }
    /// Источник без серверных папок.
    func folderUpdates() -> AsyncStream<[ChatFolder]> { AsyncStream { $0.yield([]); $0.finish() } }
    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без общей разметки: уходят только анимодзи и упоминания.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, formatting: [TextSpan]) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(
            chatId: chatId, text: text, clientId: clientId, replyTo: replyTo,
            animoji: CoreAnimojiMark.marks(formatting), mentions: CoreMentionMark.marks(formatting)
        )
    }
    /// Источник без разметки при правке: уходит только текст.
    func editMessage(chatId: String, messageId: String, text: String, formatting: [TextSpan]) async -> Result<MessageRecord, MaxAPIError> {
        await editMessage(chatId: chatId, messageId: messageId, text: text)
    }
    /// Источник без ответа по каждому id: удалилось всё или ничего.
    func deleteSelection(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<CoreDeleteResult, MaxAPIError> {
        await deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone).map { _ in CoreDeleteResult(deleted: messageIds) }
    }
    func deletePlan(chatId: String, messageIds: [String]) async -> CoreDeletePlan? { nil }
    func editTimeoutSeconds() async -> Int64 { 0 }
    func chatRights(chatId: String) async -> CoreChatRights? { nil }
    /// Источник без реакций: изменения откатываются, каталог пуст.
    func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError> {
        .failure(.invalidResponse)
    }
    func reactionUsers(chatId: String, messageId: String) async -> Result<[ReactionUser], MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без «Кем прочитано».
    func messageReaders(chatId: String, messageId: String) async -> Result<[MessageReader], MaxAPIError> {
        .failure(.invalidResponse)
    }
    func readersAvailable(chatId: String) -> Bool { false }
    func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func reactionCatalog() async -> Result<[String], MaxAPIError> { .failure(.invalidResponse) }
    /// Источник без поиска на сервере.
    func searchPublic(query: String) async -> Result<[ChatSearchResult], MaxAPIError> { .failure(.invalidResponse) }
    func searchMessages(query: String) async -> Result<[FoundMessage], MaxAPIError> { .failure(.invalidResponse) }
    func createGroup(title: String, memberIds: [String]) async -> Result<ChatRecord?, MaxAPIError> { .failure(.invalidResponse) }
    func createChannel(title: String) async -> Result<ChatRecord?, MaxAPIError> { .failure(.invalidResponse) }
    func joinByLink(_ link: String) async -> Result<ChatRecord?, MaxAPIError> { .failure(.invalidResponse) }
    func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func leaveChat(chatId: String) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без загрузок.
    func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                         progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError> {
        .failure(.invalidResponse)
    }
    /// Источник без ответов отправляет просто текст.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId)
    }
    /// Источник без анимодзи отправляет их обычными эмодзи.
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, animoji: [CoreAnimojiMark]) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: replyTo)
    }
    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, animoji: [CoreAnimojiMark], mentions: [CoreMentionMark]) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: replyTo, animoji: animoji)
    }
    func pinMessage(chatId: String, messageId: String) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func pinnedMessages(chatId: String) async -> Result<[ChatPin], MaxAPIError> { .failure(.invalidResponse) }
    func updatePinned(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async -> Result<Void, MaxAPIError> {
        .failure(.invalidResponse)
    }
    func scheduleMessage(chatId: String, text: String, sendAtMs: Int64) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func scheduledMessages(chatId: String) async -> Result<[FoundMessage], MaxAPIError> { .failure(.invalidResponse) }
    func sendPoll(chatId: String, title: String, answers: [String]) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func castPollVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async -> Result<CorePollCounts, MaxAPIError> { .failure(.invalidResponse) }
    func pollUpdates(chatId: String, polls: [CorePollRef]) async -> Result<[CorePollCounts], MaxAPIError> { .failure(.invalidResponse) }
    func editScheduled(chatId: String, messageId: String, text: String, sendAtMs: Int64) async -> Result<FoundMessage, MaxAPIError> { .failure(.invalidResponse) }
    func cancelScheduled(chatId: String, messageIds: [String]) async -> Result<Void, MaxAPIError> { .failure(.invalidResponse) }
    func searchInChat(chatId: String, query: String) async -> Result<[FoundMessage], MaxAPIError> { .failure(.invalidResponse) }
    func chatMembers(chatId: String) async -> Result<[CoreChatMember], MaxAPIError> { .failure(.invalidResponse) }
    func botCommands(botId: String) async -> Result<[CoreBotCommand], MaxAPIError> { .failure(.invalidResponse) }
    func pressButton(chatId: String, messageId: String, callbackId: String, payload: String?) async -> Result<CoreButtonAnswer, MaxAPIError> {
        .failure(.invalidResponse)
    }
}

/// Клиент API Max поверх `MaxCore`. Типы Kotlin сюда не попадают.
public final class MaxAPIClient: MaxAPI, Sendable {
    private let core: any MaxCore

    public init(core: any MaxCore) {
        self.core = core
    }

    public func fetchChatList() async -> Result<ChatListPage, MaxAPIError> {
        await catching {
            let list = try await core.loadChatList()
            // Строки списка полные: пустое последнее сообщение значит «сообщений нет».
            let records = list.chats.map { chat in
                var record = CoreMapping.chat(chat)
                record.lastKnown = true
                return record
            }
            return ChatListPage(records: records, complete: list.complete)
        }
    }

    public func refreshPhotoURLs(_ items: [PhotoRefreshKey]) async -> Result<[RefreshedPhotoURL], MaxAPIError> {
        await catching { try await core.refreshPhotoURLs(items) }
    }

    public func fetchChats() async -> Result<[ChatRecord], MaxAPIError> {
        await catching {
            // Строки списка полные: пустое последнее сообщение значит «сообщений нет».
            try await core.loadChats().map { chat in
                var record = CoreMapping.chat(chat)
                record.lastKnown = true
                return record
            }
        }
    }

    public func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError> {
        await catching {
            try CoreMapping.chat(await core.loadChat(id: id))
        }
    }

    public func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadHistory(chatId: chatId, beforeMs: before?.unixMillis ?? 0, limit: limit)
            return page.map(CoreMapping.message)
        }
    }

    public func fetchOpenedMessages(chatId: String, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadOpenedHistory(chatId: chatId, limit: limit)
            return page.map(CoreMapping.message)
        }
    }

    public func fetchOlderMessages(chatId: String, before: Date, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadOlderHistory(chatId: chatId, beforeMs: before.unixMillis, limit: limit)
            return page.map(CoreMapping.message)
        }
    }

    public func fetchMessagesAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadHistoryAround(
                chatId: chatId, messageId: messageId, fromMs: at?.unixMillis ?? 0,
                forward: forward, backward: backward
            )
            return page.map(CoreMapping.message)
        }
    }

    public func fetchSharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError> {
        await catching {
            let page = try await core.loadSharedMedia(
                chatId: chatId, anchorId: anchorId, attachTypes: types.map(\.rawValue),
                forward: forward, backward: backward
            )
            return page.map(CoreMapping.message)
        }
    }

    public func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: nil)
    }

    public func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError> {
        _ = clientId
        return await catching {
            let sent: CoreMessage
            if let replyTo, !replyTo.isEmpty {
                sent = try await core.sendText(chatId: chatId, text: text, replyTo: replyTo)
            } else {
                sent = try await core.sendText(chatId: chatId, text: text)
            }
            return SentMessage(serverId: sent.id, timestamp: Date(unixMillis: sent.timeMs))
        }
    }

    public func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, animoji: [CoreAnimojiMark]) async -> Result<SentMessage, MaxAPIError> {
        await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: replyTo, animoji: animoji, mentions: [])
    }

    public func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, animoji: [CoreAnimojiMark], mentions: [CoreMentionMark]) async -> Result<SentMessage, MaxAPIError> {
        guard !animoji.isEmpty || !mentions.isEmpty else {
            return await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: replyTo)
        }
        return await catching {
            let sent = try await core.sendRichText(chatId: chatId, text: text, replyTo: replyTo ?? "", animoji: animoji, mentions: mentions)
            return SentMessage(serverId: sent.id, timestamp: Date(unixMillis: sent.timeMs))
        }
    }

    /// Только анимодзи и упоминания уходят прежним вызовом; остальная разметка — списком
    /// элементов сервера.
    public func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?, formatting: [TextSpan]) async -> Result<SentMessage, MaxAPIError> {
        let animoji = CoreAnimojiMark.marks(formatting)
        let mentions = CoreMentionMark.marks(formatting)
        guard formatting.contains(where: { $0.kind != .animoji && $0.kind != .mention }) else {
            return await sendMessage(chatId: chatId, text: text, clientId: clientId, replyTo: replyTo, animoji: animoji, mentions: mentions)
        }
        let elements = MessageMarkup.json(MessageMarkup.elements(formatting, text: text))
        return await catching {
            let sent = try await core.sendFormattedText(chatId: chatId, text: text, elementsJSON: elements, replyTo: replyTo ?? "")
            return SentMessage(serverId: sent.id, timestamp: Date(unixMillis: sent.timeMs))
        }
    }

    public func pinMessage(chatId: String, messageId: String) async -> Result<Void, MaxAPIError> {
        await catching { try await core.pinMessage(chatId: chatId, messageId: messageId) }
    }

    public func pinnedMessages(chatId: String) async -> Result<[ChatPin], MaxAPIError> {
        await catching {
            let messages = try await core.pinnedMessages(chatId: chatId, from: "", backward: -1)
            return messages.reversed().compactMap { message in
                let id = message.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return nil }
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return ChatPin(messageId: id, text: text.isEmpty ? "Сообщение" : text)
            }
        }
    }

    public func updatePinned(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.updatePinned(chatId: chatId, action: action, messageIds: messageIds, forMe: forMe, notify: notify)
        }
    }

    public func scheduleMessage(chatId: String, text: String, sendAtMs: Int64) async -> Result<Void, MaxAPIError> {
        await catching { try await core.scheduleMessage(chatId: chatId, text: text, sendAtMs: sendAtMs) }
    }

    public func scheduledMessages(chatId: String) async -> Result<[FoundMessage], MaxAPIError> {
        await catching {
            try await core.scheduledMessages(chatId: chatId).map { found in
                FoundMessage(
                    chatId: found.chatId,
                    messageId: found.messageId,
                    senderId: found.senderId,
                    text: found.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: found.timeMs > 0 ? Date(timeIntervalSince1970: TimeInterval(found.timeMs) / 1000) : nil
                )
            }
        }
    }

    public func sendPoll(chatId: String, title: String, answers: [String]) async -> Result<Void, MaxAPIError> {
        await catching { _ = try await core.sendPoll(chatId: chatId, title: title, answers: answers) }
    }

    public func votePoll(chatId: String, messageId: String, pollId: String, answerId: String) async -> Result<Void, MaxAPIError> {
        await catching { try await core.votePoll(chatId: chatId, messageId: messageId, pollId: pollId, answerId: answerId) }
    }

    public func castPollVotes(chatId: String, messageId: String, pollId: String, answerIds: [String]) async -> Result<CorePollCounts, MaxAPIError> {
        await catching { try await core.castPollVotes(chatId: chatId, messageId: messageId, pollId: pollId, answerIds: answerIds) }
    }

    public func pollUpdates(chatId: String, polls: [CorePollRef]) async -> Result<[CorePollCounts], MaxAPIError> {
        await catching { try await core.pollUpdates(chatId: chatId, polls: polls) }
    }

    public func editScheduled(chatId: String, messageId: String, text: String, sendAtMs: Int64) async -> Result<FoundMessage, MaxAPIError> {
        await catching { Self.found(try await core.editScheduled(chatId: chatId, messageId: messageId, text: text, sendAtMs: sendAtMs), chatId: chatId) }
    }

    public func cancelScheduled(chatId: String, messageIds: [String]) async -> Result<Void, MaxAPIError> {
        await catching { try await core.cancelScheduled(chatId: chatId, messageIds: messageIds) }
    }

    private static func found(_ found: CoreFoundMessage, chatId: String) -> FoundMessage {
        FoundMessage(
            chatId: found.chatId.isEmpty ? chatId : found.chatId,
            messageId: found.messageId,
            senderId: found.senderId,
            text: found.text.trimmingCharacters(in: .whitespacesAndNewlines),
            date: found.timeMs > 0 ? Date(timeIntervalSince1970: TimeInterval(found.timeMs) / 1000) : nil
        )
    }

    public func searchInChat(chatId: String, query: String) async -> Result<[FoundMessage], MaxAPIError> {
        await catching {
            try await core.searchInChat(chatId: chatId, query: query).map { found in
                FoundMessage(
                    chatId: found.chatId.isEmpty ? chatId : found.chatId,
                    messageId: found.messageId,
                    senderId: found.senderId,
                    text: found.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    date: found.timeMs > 0 ? Date(timeIntervalSince1970: TimeInterval(found.timeMs) / 1000) : nil
                )
            }
        }
    }

    public func chatMembers(chatId: String) async -> Result<[CoreChatMember], MaxAPIError> {
        await catching { try await core.chatMembers(chatId: chatId) }
    }

    public func botCommands(botId: String) async -> Result<[CoreBotCommand], MaxAPIError> {
        await catching { try await core.botCommands(botId: botId) }
    }

    public func pressButton(chatId: String, messageId: String, callbackId: String, payload: String?) async -> Result<CoreButtonAnswer, MaxAPIError> {
        await catching { try await core.pressButton(chatId: chatId, messageId: messageId, callbackId: callbackId, payload: payload ?? "") }
    }

    public func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError> {
        await catching {
            CoreMapping.message(try await core.editMessage(chatId: chatId, messageId: messageId, text: text))
        }
    }

    public func editMessage(chatId: String, messageId: String, text: String, formatting: [TextSpan]) async -> Result<MessageRecord, MaxAPIError> {
        let elements = MessageMarkup.json(MessageMarkup.elements(formatting, text: text))
        return await catching {
            CoreMapping.message(try await core.editMessage(chatId: chatId, messageId: messageId, text: text, elementsJSON: elements))
        }
    }

    public func deleteSelection(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<CoreDeleteResult, MaxAPIError> {
        await catching {
            try await core.deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone, postId: "")
        }
    }

    public func deletePlan(chatId: String, messageIds: [String]) async -> CoreDeletePlan? {
        await core.deletePlan(chatId: chatId, messageIds: messageIds)
    }

    public func editTimeoutSeconds() async -> Int64 {
        await core.editTimeoutSeconds()
    }

    public func chatRights(chatId: String) async -> CoreChatRights? {
        await core.chatRights(chatId: chatId)
    }

    public func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.deleteMessages(chatId: chatId, messageIds: messageIds, forEveryone: forEveryone)
        }
    }

    public func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError> {
        await catching {
            CoreMapping.message(try await core.forwardMessage(toChatId: toChatId, fromChatId: fromChatId, messageId: messageId))
        }
    }

    public func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.setChatMuted(chatId: chatId, muted: muted)
        }
    }

    public func chatMute(chatId: String) async -> ChatMuteState {
        let muted = await core.isChatMuted(chatId: chatId)
        let until = await core.chatMuteUntil(chatId: chatId)
        return ChatMuteState(muted: muted, untilMs: until == Int64.min ? 0 : until)
    }

    public func searchPublic(query: String) async -> Result<[ChatSearchResult], MaxAPIError> {
        await catching {
            try await core.searchPublic(query: query, from: 0, count: Self.searchPageSize).map(CoreMapping.searchResult)
        }
    }

    /// Сколько публичных чатов просить за раз.
    static let searchPageSize = 20

    public func searchMessages(query: String) async -> Result<[FoundMessage], MaxAPIError> {
        await catching {
            try await core.searchMessages(query: query, count: Self.messageSearchCount).compactMap(CoreMapping.foundMessage)
        }
    }

    /// Сколько найденных сообщений просить у сервера.
    static let messageSearchCount = 50

    public func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError> {
        guard let messageId, !messageId.isEmpty else { return .success(()) }
        return await catching {
            try await core.markRead(chatId: chatId, messageId: messageId)
        }
    }

    public func markRead(chatId: String, messageId: String?, at mark: Int64) async -> Result<CoreReadMark?, MaxAPIError> {
        guard let messageId, !messageId.isEmpty else { return .success(nil) }
        return await catching {
            let reply = try await core.markRead(chatId: chatId, messageId: messageId, mark: max(mark, 0))
            return reply.mark > 0 ? reply : nil
        }
    }

    public func markUnread(chatId: String, from date: Date) async -> Result<Int, MaxAPIError> {
        await catching {
            try await core.markUnread(chatId: chatId, mark: date.unixMillis)
        }
    }

    public func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError> {
        await catching {
            let json = try await core.setReaction(chatId: chatId, messageId: messageId, postId: postId, emoji: emoji ?? "")
            return MessageContentCodec.reactionUpdate(json)
        }
    }

    public func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError> {
        await catching {
            try await core.loadReactions(chatId: chatId, messageIds: messageIds)
                .compactMapValues(MessageContentCodec.reactionUpdate)
        }
    }

    public func reactionUsers(chatId: String, messageId: String) async -> Result<[ReactionUser], MaxAPIError> {
        await catching {
            try await core.loadReactionUsers(chatId: chatId, messageId: messageId)
        }
    }

    public func messageReaders(chatId: String, messageId: String) async -> Result<[MessageReader], MaxAPIError> {
        await catching {
            try await core.loadMessageReaders(chatId: chatId, messageId: messageId)
        }
    }

    public func readersAvailable(chatId: String) -> Bool {
        core.isReadersAvailable(chatId: chatId)
    }

    public func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError> {
        await catching {
            try await core.transcribeVoice(chatId: chatId, messageId: messageId, audioId: audioId)
        }
    }

    public func reactionCatalog() async -> Result<[String], MaxAPIError> {
        await catching {
            try await core.loadReactionCatalog()
        }
    }

    public func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                                progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError> {
        let reply = replyTo.flatMap { Int64($0) == nil ? nil : $0 } ?? ""
        if let contact = drafts.first(where: { $0.kind == .contact }) {
            // Карточка контакта — отдельное сообщение: у него нет файла и подписи.
            guard drafts.count == 1, !contact.contactId.isEmpty else { return .failure(.invalidResponse) }
            return await catching {
                CoreMapping.message(try await core.sendContact(chatId: chatId, contactId: contact.contactId, replyTo: reply))
            }
        }
        if let sticker = drafts.first(where: { $0.kind == .sticker }) {
            // Стикер — отдельное сообщение без подписи.
            guard drafts.count == 1, !sticker.contactId.isEmpty else { return .failure(.invalidResponse) }
            return await catching {
                CoreMapping.message(try await core.sendSticker(chatId: chatId, stickerId: sticker.contactId, replyTo: reply))
            }
        }
        if let recording = drafts.first(where: \.isRecording) {
            // Голосовое и кружок — отдельное сообщение со своим слотом загрузки.
            guard drafts.count == 1, !recording.path.isEmpty else { return .failure(.invalidResponse) }
            return await catching {
                CoreMapping.message(try await core.sendRecording(
                    chatId: chatId, path: recording.path, kind: recording.kind.rawValue,
                    durationMs: recording.durationMs, wave: recording.waveform, replyTo: reply, progress: progress
                ))
            }
        }
        let items = drafts.map { draft in
            CoreOutgoingMedia(path: draft.path, kind: draft.kind.rawValue, fileName: draft.fileName)
        }
        guard !items.isEmpty, !items.contains(where: { $0.path.isEmpty }) else { return .failure(.invalidResponse) }
        return await catching {
            CoreMapping.message(try await core.sendMedia(chatId: chatId, items: items, caption: caption, replyTo: reply, progress: progress))
        }
    }

    public func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError> {
        await catching {
            try await core.setPinnedChats(chatIds)
        }
    }

    public func createGroup(title: String, memberIds: [String]) async -> Result<ChatRecord?, MaxAPIError> {
        await catching {
            guard let chat = try await core.createGroup(title: title, memberIds: memberIds) else { return nil }
            return CoreMapping.chat(chat)
        }
    }

    public func createChannel(title: String) async -> Result<ChatRecord?, MaxAPIError> {
        await catching {
            guard let chat = try await core.createChannel(title: title) else { return nil }
            return CoreMapping.chat(chat)
        }
    }

    public func joinByLink(_ link: String) async -> Result<ChatRecord?, MaxAPIError> {
        await catching {
            CoreMapping.chat(try await core.joinByLink(link))
        }
    }

    public func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.deleteChat(chatId: chatId, lastEventTimeMs: lastEventTimeMs, forEveryone: forEveryone)
        }
    }

    public func leaveChat(chatId: String) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.leaveChat(chatId: chatId)
        }
    }

    public func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        await catching {
            try await core.clearHistory(chatId: chatId, lastEventTimeMs: lastEventTimeMs, forEveryone: forEveryone)
        }
    }

    public func folderUpdates() -> AsyncStream<[ChatFolder]> {
        let source = core.folders()
        return AsyncStream { continuation in
            let task = Task {
                for await folders in source {
                    continuation.yield(folders.filter { !$0.isAllChats }.map(\.chatFolder))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func catching<T>(_ body: () async throws -> T) async -> Result<T, MaxAPIError> {
        do {
            return .success(try await body())
        } catch {
            return .failure(CoreMapping.apiError(error))
        }
    }
}

/// Звук чата из конфига ядра: `muted` `1` без звука, `0` со звуком, `-1` неизвестно;
/// `untilMs` — сырой `dontDisturbUntil` (`-1` насовсем, больше нуля — конец в мс, `0` — нет срока
/// или неизвестно).
public struct ChatMuteState: Sendable, Equatable {
    public var muted: Int
    public var untilMs: Int64

    public init(muted: Int, untilMs: Int64 = 0) {
        self.muted = muted
        self.untilMs = untilMs
    }

    public static let unknown = ChatMuteState(muted: -1)
}
