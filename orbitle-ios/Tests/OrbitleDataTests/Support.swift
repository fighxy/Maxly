import Foundation
import OrbitleDomain
@testable import OrbitleData

/// Фейковый API: отвечает заранее заданными результатами и считает вызовы.
actor FakeMaxAPI: MaxAPI {
    var history: [MessageRecord] = []
    /// Ответы на sendMessage по порядку. Когда кончаются, повторяется последний.
    var sendResults: [Result<SentMessage, MaxAPIError>] = [.success(SentMessage(serverId: "srv-1", timestamp: .now))]
    private(set) var sendCalls = 0

    func setSendResults(_ results: [Result<SentMessage, MaxAPIError>]) {
        sendResults = results
    }

    func setHistory(_ records: [MessageRecord]) {
        history = records
    }

    var chats: [ChatRecord] = []

    func setChats(_ records: [ChatRecord]) {
        chats = records
    }

    /// Если задан, запросы чатов и истории ждут, пока тест его не откроет.
    var fetchGate: Gate?

    func setFetchGate(_ gate: Gate?) { fetchGate = gate }

    func fetchChats() async -> Result<[ChatRecord], MaxAPIError> {
        if let fetchGate { await fetchGate.wait() }
        return .success(chats)
    }

    /// Ошибка `CHAT_INFO`, например нет сети.
    var chatError: MaxAPIError?
    private(set) var chatRequests: [String] = []
    private(set) var markReadCalls: [String] = []

    func setChatError(_ error: MaxAPIError?) { chatError = error }

    func fetchChat(id: String) async -> Result<ChatRecord, MaxAPIError> {
        chatRequests.append(id)
        if let fetchGate { await fetchGate.wait() }
        if let chatError { return .failure(chatError) }
        if let chat = chats.first(where: { $0.id == id }) {
            return .success(chat)
        }
        return .failure(.invalidResponse)
    }

    /// Ошибка загрузки истории, например нет сети.
    var historyError: MaxAPIError?

    func setHistoryError(_ error: MaxAPIError?) { historyError = error }

    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        if let fetchGate { await fetchGate.wait() }
        if let historyError { return .failure(historyError) }
        let older = history
            .filter { message in
                message.chatId == chatId && (before.map { message.timestamp < $0 } ?? true)
            }
            .sorted { $0.timestamp > $1.timestamp }
        return .success(Array(older.prefix(limit)))
    }

    /// Ответ на запрос общих медиа и сами запросы: типы, якорь, вперёд, назад.
    var sharedMediaResult: Result<[MessageRecord], MaxAPIError> = .failure(.invalidResponse)
    private(set) var sharedMediaRequests: [([SharedAttachType], String, Int, Int)] = []

    func setSharedMediaResult(_ result: Result<[MessageRecord], MaxAPIError>) { sharedMediaResult = result }

    func fetchSharedMedia(chatId: String, types: [SharedAttachType], anchorId: String, forward: Int, backward: Int) async -> Result<[MessageRecord], MaxAPIError> {
        sharedMediaRequests.append((types, anchorId, forward, backward))
        return sharedMediaResult
    }

    /// Если задан, отправка ждёт, пока тест его не откроет.
    var sendGate: Gate?

    func setSendGate(_ gate: Gate?) { sendGate = gate }

    /// `replyTo` каждой отправки по порядку.
    private(set) var sentReplies: [String?] = []
    /// Удаления: серверные id и «у всех».
    private(set) var deletions: [([String], Bool)] = []
    var deleteResult: Result<Void, MaxAPIError> = .success(())
    /// Ответ на пересылку.
    var forwardResult: Result<MessageRecord, MaxAPIError> = .failure(.invalidResponse)

    func setDeleteResult(_ result: Result<Void, MaxAPIError>) { deleteResult = result }
    /// Ответ на правку и сами правки (серверный id, текст).
    var editResult: Result<MessageRecord, MaxAPIError> = .failure(.invalidResponse)
    private(set) var edits: [(String, String)] = []
    func setEditResult(_ result: Result<MessageRecord, MaxAPIError>) { editResult = result }

    func editMessage(chatId: String, messageId: String, text: String) async -> Result<MessageRecord, MaxAPIError> {
        edits.append((messageId, text))
        return editResult
    }
    func setForwardResult(_ result: Result<MessageRecord, MaxAPIError>) { forwardResult = result }

    func deleteMessages(chatId: String, messageIds: [String], forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        deletions.append((messageIds, forEveryone))
        return deleteResult
    }

    func forwardMessage(toChatId: String, fromChatId: String, messageId: String) async -> Result<MessageRecord, MaxAPIError> {
        forwardResult
    }

    func sendMessage(chatId: String, text: String, clientId: String, replyTo: String?) async -> Result<SentMessage, MaxAPIError> {
        sentReplies.append(replyTo)
        return await sendMessage(chatId: chatId, text: text, clientId: clientId)
    }

    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        if let sendGate { await sendGate.wait() }
        let index = min(sendCalls, sendResults.count - 1)
        sendCalls += 1
        return sendResults[index]
    }

    func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError> {
        markReadCalls.append(chatId)
        return .success(())
    }

    private(set) var markUnreadCalls: [String] = []
    /// Ответ сервера на пометку «непрочитано»: число непрочитанных или ошибка.
    var unreadReply: Result<Int, MaxAPIError> = .success(2)

    func set(unreadReply: Result<Int, MaxAPIError>) { self.unreadReply = unreadReply }

    func markUnread(chatId: String, from date: Date) async -> Result<Int, MaxAPIError> {
        markUnreadCalls.append(chatId)
        return unreadReply
    }

    /// Списки закреплённых, ушедшие на сервер, по порядку.
    private(set) var pinCalls: [[String]] = []
    /// Ошибка следующих запросов закреплённых. `nil`: сервер подтверждает присланный список.
    var pinError: MaxAPIError?
    /// Если задан, ответ сервера на закреплённые ждёт, пока тест его не откроет.
    var pinGate: Gate?

    func setPinError(_ error: MaxAPIError?) { pinError = error }
    func setPinGate(_ gate: Gate?) { pinGate = gate }

    func setPinnedChats(_ chatIds: [String]) async -> Result<[String], MaxAPIError> {
        pinCalls.append(chatIds)
        if let pinGate { await pinGate.wait() }
        if let pinError { return .failure(pinError) }
        return .success(chatIds)
    }

    // MARK: Реакции

    struct ReactionCall: Equatable, Sendable {
        var messageId: String
        var postId: String
        var emoji: String?
    }

    /// Ответы на реакции по порядку. Когда кончаются, повторяется последний.
    var reactionResults: [Result<ReactionUpdate?, MaxAPIError>] = [.success(nil)]
    private(set) var reactionCalls: [ReactionCall] = []
    /// Если задан, ответ на реакцию ждёт, пока тест его не откроет.
    var reactionGate: Gate?
    var fetchedReactions: Result<[String: ReactionUpdate], MaxAPIError> = .success([:])
    private(set) var reactionFetches: [[String]] = []

    func setReactionResults(_ results: [Result<ReactionUpdate?, MaxAPIError>]) { reactionResults = results }
    func setReactionGate(_ gate: Gate?) { reactionGate = gate }
    func setFetchedReactions(_ result: Result<[String: ReactionUpdate], MaxAPIError>) { fetchedReactions = result }

    func setReaction(chatId: String, messageId: String, postId: String, emoji: String?) async -> Result<ReactionUpdate?, MaxAPIError> {
        let index = min(reactionCalls.count, reactionResults.count - 1)
        reactionCalls.append(ReactionCall(messageId: messageId, postId: postId, emoji: emoji))
        let result = reactionResults[index]
        if let reactionGate { await reactionGate.wait() }
        return result
    }

    func fetchReactions(chatId: String, messageIds: [String]) async -> Result<[String: ReactionUpdate], MaxAPIError> {
        reactionFetches.append(messageIds)
        return fetchedReactions
    }

    func reactionCatalog() async -> Result<[String], MaxAPIError> { .success(["👍", "👍", "", "🔥"]) }

    // MARK: Расшифровка

    var transcription: Result<CoreTranscription, MaxAPIError> = .success(CoreTranscription(status: 1, text: ""))
    private(set) var transcriptionCalls: [String] = []
    func setTranscription(_ result: Result<CoreTranscription, MaxAPIError>) { transcription = result }

    func transcribe(chatId: String, messageId: String, audioId: String) async -> Result<CoreTranscription, MaxAPIError> {
        transcriptionCalls.append("\(chatId):\(messageId):\(audioId)")
        return transcription
    }

    // MARK: Вложения

    struct AttachmentCall: Equatable, Sendable {
        var chatId: String
        var drafts: [AttachmentDraft]
        var caption: String
        var replyTo: String?
    }

    /// Ответы на отправку вложений по порядку; когда кончаются, повторяется последний.
    var attachmentResults: [Result<MessageRecord, MaxAPIError>] = []
    private(set) var attachmentCalls: [AttachmentCall] = []
    /// Пока `true`, загрузка «идёт»: ответа нет, отмена задачи её прерывает.
    var holdUploads = false

    func setAttachmentResults(_ results: [Result<MessageRecord, MaxAPIError>]) { attachmentResults = results }
    func setHoldUploads(_ value: Bool) { holdUploads = value }

    func sendAttachments(chatId: String, drafts: [AttachmentDraft], caption: String, replyTo: String?,
                         progress: @escaping @Sendable (Double) -> Void) async -> Result<MessageRecord, MaxAPIError> {
        attachmentCalls.append(AttachmentCall(chatId: chatId, drafts: drafts, caption: caption, replyTo: replyTo))
        progress(0.25)
        while holdUploads {
            if Task.isCancelled { return .failure(.cancelled) }
            try? await Task.sleep(for: .milliseconds(5))
        }
        progress(1)
        guard !attachmentResults.isEmpty else { return .failure(.invalidResponse) }
        return attachmentResults[min(attachmentCalls.count - 1, attachmentResults.count - 1)]
    }

    /// Запросы звука чатов: id и «без звука».
    private(set) var muteCalls: [(String, Bool)] = []
    private(set) var searchCalls: [String] = []
    var searchResult: Result<[ChatSearchResult], MaxAPIError> = .success([])

    func searchPublic(query: String) async -> Result<[ChatSearchResult], MaxAPIError> {
        searchCalls.append(query)
        return searchResult
    }

    func setSearchResult(_ result: Result<[ChatSearchResult], MaxAPIError>) {
        searchResult = result
    }

    private(set) var messageSearchCalls: [String] = []
    var messageSearchResult: Result<[FoundMessage], MaxAPIError> = .success([])

    func searchMessages(query: String) async -> Result<[FoundMessage], MaxAPIError> {
        messageSearchCalls.append(query)
        return messageSearchResult
    }

    func setMessageSearchResult(_ result: Result<[FoundMessage], MaxAPIError>) {
        messageSearchResult = result
    }

    private(set) var groupCalls: [(String, [String])] = []
    private(set) var channelCalls: [String] = []
    private(set) var linkCalls: [String] = []
    var createdGroup: ChatRecord?
    var createdChannel: ChatRecord?
    var joinedChat: ChatRecord?
    var createError: MaxAPIError?

    func createGroup(title: String, memberIds: [String]) async -> Result<ChatRecord?, MaxAPIError> {
        groupCalls.append((title, memberIds))
        if let createError { return .failure(createError) }
        return .success(createdGroup)
    }

    func createChannel(title: String) async -> Result<ChatRecord?, MaxAPIError> {
        channelCalls.append(title)
        if let createError { return .failure(createError) }
        return .success(createdChannel)
    }

    private(set) var chatDeletes: [(String, Int64, Bool)] = []
    private(set) var historyClears: [(String, Int64, Bool)] = []
    var chatDeleteResult: Result<Void, MaxAPIError> = .success(())
    var historyClearResult: Result<Void, MaxAPIError> = .success(())

    func deleteChat(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        chatDeletes.append((chatId, lastEventTimeMs, forEveryone))
        return chatDeleteResult
    }

    func clearHistory(chatId: String, lastEventTimeMs: Int64, forEveryone: Bool) async -> Result<Void, MaxAPIError> {
        historyClears.append((chatId, lastEventTimeMs, forEveryone))
        return historyClearResult
    }

    func joinByLink(_ link: String) async -> Result<ChatRecord?, MaxAPIError> {
        linkCalls.append(link)
        if let createError { return .failure(createError) }
        return .success(joinedChat)
    }

    func setCreatedGroup(_ record: ChatRecord?) { createdGroup = record }
    func setCreatedChannel(_ record: ChatRecord?) { createdChannel = record }
    func setJoinedChat(_ record: ChatRecord?) { joinedChat = record }
    func setCreateError(_ error: MaxAPIError?) { createError = error }
    var muteError: MaxAPIError?
    func setMuteError(_ error: MaxAPIError?) { muteError = error }

    func setChatMuted(chatId: String, muted: Bool) async -> Result<Void, MaxAPIError> {
        muteCalls.append((chatId, muted))
        if let muteError { return .failure(muteError) }
        return .success(())
    }
}

/// Репозиторий сообщений на базе в памяти с подключённой очередью без реальных задержек.
func makeMessageStack(api: FakeMaxAPI) async throws -> (MessageRepositoryImpl, OutboxQueue) {
    let stack = try SwiftDataStack(inMemory: true)
    let repository = MessageRepositoryImpl.make(stack: stack, api: api)
    let outbox = OutboxQueue(api: api, sleep: { _ in })
    await repository.attach(outbox: outbox)
    return (repository, outbox)
}

/// `count` сообщений в чате с временем 1, 2, 3… секунды от начала эпохи.
func makeHistory(chatId: String, count: Int) -> [MessageRecord] {
    (0..<count).map { index in
        MessageRecord(
            id: "m\(index)",
            serverId: "m\(index)",
            chatId: chatId,
            authorId: index.isMultiple(of: 2) ? "alice" : "bob",
            text: "Сообщение \(index)",
            timestamp: Date(timeIntervalSince1970: TimeInterval(index + 1)),
            status: .sent,
            mediaId: index.isMultiple(of: 10) ? "media\(index)" : nil
        )
    }
}

/// Чат для тестов.
func makeChat(id: String = "c1") -> ChatRecord {
    ChatRecord(
        id: id,
        title: "Команда Orbitle",
        type: .group,
        lastMessageId: "m99",
        unreadCount: 3,
        updatedAt: Date(timeIntervalSince1970: 100),
        preview: "Последнее"
    )
}

/// Задержка, которую тест открывает сам: так видно ответ ядра, пришедший после действия пользователя.
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

/// Ждёт условие не дольше `timeout`. Нужен там, где значение приходит из фоновой задачи.
func eventually(timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
