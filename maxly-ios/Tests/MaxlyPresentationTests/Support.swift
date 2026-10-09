import Foundation
import MaxlyDomain
@testable import MaxlyPresentation

/// Задержка, которую тест открывает сам: так видно состояние экрана во время запроса.
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

/// Ждёт условие не дольше `timeout`, отпуская главный актор между проверками.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

/// Часы, которые двигает тест.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_790_000_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Сервис входа: шаги публикуются в поток так же, как у `SessionManager`.
actor FakeAuthService: AuthService {
    nonisolated let stream: AsyncStream<AuthPhase>
    nonisolated let continuation: AsyncStream<AuthPhase>.Continuation

    var codeLength: Int? = 6
    var afterVerify: AuthPhase = .signedIn(userId: "1")
    var afterPassword: AuthPhase = .signedIn(userId: "1")
    var requestError: MaxlyError?
    var resendError: MaxlyError?
    var verifyError: MaxlyError?
    var passwordError: MaxlyError?
    var registerError: MaxlyError?
    var gate: Gate?
    private var attempt = 0
    private(set) var calls: [String] = []

    init() {
        let pair = AsyncStream.makeStream(of: AuthPhase.self)
        stream = pair.stream
        continuation = pair.continuation
    }

    nonisolated func phases() -> AsyncStream<AuthPhase> { stream }
    nonisolated func publish(_ phase: AuthPhase) { continuation.yield(phase) }

    var isAuthorized: Bool { false }

    func restoreSession() async {}

    func requestCode(phone: String) async throws(MaxlyError) {
        calls.append("code \(phone)")
        try await pass(requestError)
        continuation.yield(.codeSent(codeLength: codeLength))
    }

    func resendCode() async throws(MaxlyError) {
        calls.append("resend")
        try await pass(resendError)
        continuation.yield(.codeSent(codeLength: codeLength))
    }

    func verifyCode(_ code: String) async throws(MaxlyError) {
        calls.append("verify \(code)")
        try await pass(verifyError)
        continuation.yield(afterVerify)
    }

    func submitPassword(_ password: String) async throws(MaxlyError) {
        calls.append("password \(password)")
        try await pass(passwordError)
        continuation.yield(afterPassword)
    }

    func register(firstName: String, lastName: String) async throws(MaxlyError) {
        calls.append("register \(firstName)|\(lastName)")
        try await pass(registerError)
        continuation.yield(.signedIn(userId: "new"))
    }

    func cancelLogin() async {
        calls.append("cancel")
        attempt += 1
        continuation.yield(.signedOut)
    }

    func logout() async {
        calls.append("logout")
        continuation.yield(.signedOut)
    }

    func set(codeLength: Int?) { self.codeLength = codeLength }
    func set(afterVerify: AuthPhase) { self.afterVerify = afterVerify }
    func set(requestError: MaxlyError?) { self.requestError = requestError }
    func set(verifyError: MaxlyError?) { self.verifyError = verifyError }
    func set(passwordError: MaxlyError?) { self.passwordError = passwordError }
    func set(registerError: MaxlyError?) { self.registerError = registerError }
    func set(gate: Gate?) { self.gate = gate }

    /// Как у настоящей сессии: ответ из отменённой попытки бросает `cancelled`.
    private func pass(_ error: MaxlyError?) async throws(MaxlyError) {
        let started = attempt
        if let gate { await gate.wait() }
        if started != attempt { throw .cancelled }
        if let error { throw error }
    }
}

/// Репозиторий чатов с потоком, который наполняет тест.
actor FakeChatRepository: ChatRepository {
    nonisolated let stream: AsyncStream<[Chat]>
    nonisolated let continuation: AsyncStream<[Chat]>.Continuation
    nonisolated let folderStream: AsyncStream<[ChatFolder]>
    nonisolated let folderContinuation: AsyncStream<[ChatFolder]>.Continuation
    nonisolated let typingStream: AsyncStream<[String: [TypingActivity]]>
    nonisolated let typingContinuation: AsyncStream<[String: [TypingActivity]]>.Continuation
    nonisolated let capabilities: ChatListCapabilities

    var refreshError: MaxlyError?
    var markError: MaxlyError?
    var markGate: Gate?
    var actionError: MaxlyError?
    var refreshGate: Gate?
    var actionGate: Gate?
    var searchResults: [ChatSearchResult] = []
    var morePages = false
    private(set) var refreshCount = 0
    private(set) var marked: [String] = []
    private(set) var actions: [String] = []
    private(set) var searches: [String] = []
    private(set) var pageLoads = 0

    init(capabilities: ChatListCapabilities = []) {
        let pair = AsyncStream.makeStream(of: [Chat].self)
        stream = pair.stream
        continuation = pair.continuation
        let folders = AsyncStream.makeStream(of: [ChatFolder].self)
        folderStream = folders.stream
        folderContinuation = folders.continuation
        let typing = AsyncStream.makeStream(of: [String: [TypingActivity]].self)
        typingStream = typing.stream
        typingContinuation = typing.continuation
        self.capabilities = capabilities
    }

    nonisolated func chats() -> AsyncStream<[Chat]> { stream }
    nonisolated func emit(_ chats: [Chat]) { continuation.yield(chats) }
    nonisolated func folders() -> AsyncStream<[ChatFolder]> { folderStream }
    nonisolated func emit(folders: [ChatFolder]) { folderContinuation.yield(folders) }
    nonisolated func typing() -> AsyncStream<[String: [TypingActivity]]> { typingStream }
    nonisolated func emit(typing: [String: [TypingActivity]]) { typingContinuation.yield(typing) }
    /// Печатающие по id, без имён и типа: начало — по порядку в списке.
    nonisolated func emit(typingIds: [String: [String]]) {
        typingContinuation.yield(typingIds.mapValues { ids in
            ids.enumerated().map { TypingActivity(userId: $1, startedAt: Date(timeIntervalSince1970: TimeInterval($0))) }
        })
    }

    func refresh() async throws(MaxlyError) {
        refreshCount += 1
        if let refreshGate { await refreshGate.wait() }
        if let refreshError { throw refreshError }
    }

    func refresh(chatId: String) async throws(MaxlyError) {}

    func markAsRead(chatId: String) async throws(MaxlyError) {
        marked.append(chatId)
        if let markGate { await markGate.wait() }
        if let markError { throw markError }
    }

    /// Отметки экрана чата: «чат:сообщение@время».
    private(set) var readMarks: [String] = []
    var readMarkError: MaxlyError?
    func set(readMarkError: MaxlyError?) { self.readMarkError = readMarkError }

    func markRead(chatId: String, messageId: String, at mark: Int64) async throws(MaxlyError) {
        readMarks.append("\(chatId):\(messageId)@\(mark)")
        if let readMarkError { throw readMarkError }
    }

    func setPinned(_ pinned: Bool, chatId: String) async throws(MaxlyError) {
        try await record("\(pinned ? "pin" : "unpin") \(chatId)")
    }

    func reorderPinned(_ chatIds: [String]) async throws(MaxlyError) {
        try await record("order \(chatIds.joined(separator: ","))")
    }

    func setMarkedUnread(_ unread: Bool, chatId: String) async throws(MaxlyError) {
        try await record("\(unread ? "unread" : "read-mark") \(chatId)")
    }

    func markUnread(chatId: String, from date: Date) async throws(MaxlyError) {
        try await record("unread-from \(chatId) \(Int(date.timeIntervalSince1970))")
    }

    func setMuted(_ muted: Bool, chatId: String) async throws(MaxlyError) {
        try await record("\(muted ? "mute" : "unmute") \(chatId)")
    }

    func setArchived(_ archived: Bool, chatId: String) async throws(MaxlyError) {
        try await record("\(archived ? "archive" : "unarchive") \(chatId)")
    }

    func delete(chatId: String, forEveryone: Bool) async throws(MaxlyError) {
        try await record("delete \(chatId) \(forEveryone)")
    }

    func clearHistory(chatId: String, forEveryone: Bool) async throws(MaxlyError) {
        try await record("clear \(chatId) \(forEveryone)")
    }

    func loadMoreChats() async throws(MaxlyError) -> Bool {
        pageLoads += 1
        return morePages
    }

    func search(query: String) async throws(MaxlyError) -> [ChatSearchResult] {
        searches.append(query)
        return searchResults
    }

    var foundMessages: [FoundMessage] = []
    var messageSearchError: MaxlyError?
    private(set) var messageSearches: [String] = []

    func searchMessages(query: String) async throws(MaxlyError) -> [FoundMessage] {
        messageSearches.append(query)
        if let messageSearchError { throw messageSearchError }
        return foundMessages
    }

    func set(foundMessages: [FoundMessage]) { self.foundMessages = foundMessages }
    func set(messageSearchError: MaxlyError?) { self.messageSearchError = messageSearchError }

    private func record(_ action: String) async throws(MaxlyError) {
        actions.append(action)
        if let actionGate { await actionGate.wait() }
        if let actionError { throw actionError }
    }

    func set(refreshError: MaxlyError?) { self.refreshError = refreshError }
    func set(markError: MaxlyError?) { self.markError = markError }
    func set(markGate: Gate?) { self.markGate = markGate }
    func set(actionError: MaxlyError?) { self.actionError = actionError }
    func set(refreshGate: Gate?) { self.refreshGate = refreshGate }
    func set(actionGate: Gate?) { self.actionGate = actionGate }
    func set(searchResults: [ChatSearchResult]) { self.searchResults = searchResults }
    func set(morePages: Bool) { self.morePages = morePages }
}

/// Недавние из поиска в памяти.
actor FakeRecentSearches: RecentSearchStore {
    private(set) var ids: [String]

    init(_ ids: [String] = []) { self.ids = ids }

    func recent() async -> [String] { ids }
    func add(chatId: String) async {
        ids.removeAll { $0 == chatId }
        ids.insert(chatId, at: 0)
    }
    func remove(chatId: String) async { ids.removeAll { $0 == chatId } }
    func clear() async { ids.removeAll() }
}

/// Черновики в памяти.
actor FakeDrafts: ChatDraftStore {
    private(set) var drafts: [String: String] = [:]
    private(set) var replies: [String: String] = [:]
    private(set) var saves = 0
    private var listeners: [AsyncStream<String>.Continuation] = []

    init(_ drafts: [String: String] = [:], replies: [String: String] = [:]) {
        self.drafts = drafts
        self.replies = replies
    }

    func draft(chatId: String) async -> String? { drafts[chatId] }
    func saveDraft(_ text: String, chatId: String) async {
        saves += 1
        drafts[chatId] = text.isEmpty ? nil : text
    }
    func draftReply(chatId: String) async -> String? { replies[chatId] }
    func saveDraftReply(_ messageId: String?, chatId: String) async { replies[chatId] = messageId }
    func draftChanges() async -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        listeners.append(continuation)
        return stream
    }

    /// Черновик поменяли «на другом устройстве».
    func changeRemotely(_ text: String?, reply: String? = nil, chatId: String) {
        drafts[chatId] = text
        replies[chatId] = reply
        for listener in listeners { listener.yield(chatId) }
    }
}

/// Источник состояния соединения, которым управляет тест.
final class FakeConnection: ConnectionStatusProvider {
    let stream: AsyncStream<ConnectionState>
    let continuation: AsyncStream<ConnectionState>.Continuation

    init(initial: ConnectionState = .online) {
        let pair = AsyncStream.makeStream(of: ConnectionState.self)
        stream = pair.stream
        continuation = pair.continuation
        continuation.yield(initial)
    }

    func connectionStates() -> AsyncStream<ConnectionState> { stream }
    func emit(_ state: ConnectionState) { continuation.yield(state) }
}

/// Репозиторий сообщений для экрана чата.
actor FakeMessageRepository: MessageRepository {
    private var searchReplies: [String: (hits: [FoundMessage], gate: Gate?, error: MaxlyError?)] = [:]
    private(set) var chatSearches: [String] = []

    func setSearch(_ query: String, hits: [FoundMessage] = [], gate: Gate? = nil, error: MaxlyError? = nil) {
        searchReplies[query] = (hits, gate, error)
    }

    func searchInChat(chatId: String, query: String) async throws(MaxlyError) -> [FoundMessage] {
        chatSearches.append(query)
        guard let reply = searchReplies[query] else { throw .invalidRequest }
        if let gate = reply.gate { await gate.wait() }
        if let error = reply.error { throw error }
        return reply.hits
    }

    var sendError: MaxlyError?
    var latestError: MaxlyError?
    private(set) var sent: [String] = []
    private(set) var replyIds: [String?] = []
    /// Лента для `messages(chatId:)`: тест кладёт в неё страницы через `emit`.
    nonisolated let feed = AsyncStream<[Message]>.makeStream()

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { feed.stream }
    nonisolated func emit(_ messages: [Message]) { feed.continuation.yield(messages) }
    /// Сколько раз окно ленты расширяли на страницу.
    private(set) var olderLoads = 0
    func loadOlder(chatId: String) async throws(MaxlyError) { olderLoads += 1 }
    /// Страницы `loadMore` по очереди; кончились — пусто.
    private var morePages: [[Message]] = []
    func queueMore(_ page: [Message]) { morePages.append(page) }
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] {
        morePages.isEmpty ? [] : morePages.removeFirst()
    }

    struct AroundRequest: Equatable {
        var messageId: String
        var at: Date?
        var forward: Int
        var backward: Int
    }

    /// Запросы окна вокруг сообщения и ответы на них по очереди; ответы кончились — ошибка.
    private(set) var aroundRequests: [AroundRequest] = []
    private var aroundPages: [[Message]] = []
    func queueAround(_ page: [Message]) { aroundPages.append(page) }
    func historyAround(chatId: String, messageId: String, at: Date?, forward: Int, backward: Int) async throws(MaxlyError) -> [Message] {
        aroundRequests.append(AroundRequest(messageId: messageId, at: at, forward: forward, backward: backward))
        guard !aroundPages.isEmpty else { throw .networkUnavailable }
        return aroundPages.removeFirst()
    }
    func fetchLatest(chatId: String) async throws(MaxlyError) {
        if let latestError { throw latestError }
    }

    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {
        sent.append(text)
        replyIds.append(replyTo)
        if let sendError { throw sendError }
    }

    func retry(messageId: String) async throws(MaxlyError) {}
    func set(sendError: MaxlyError?) { self.sendError = sendError }

    struct AttachmentSend: Equatable {
        var drafts: [AttachmentDraft]
        var caption: String
        var replyTo: String?
    }

    private(set) var attachmentSends: [AttachmentSend] = []
    private(set) var cancelledUploads: [String] = []
    var attachmentError: MaxlyError?
    private var progressContinuations: [AsyncStream<[String: Double]>.Continuation] = []

    func sendAttachments(_ drafts: [AttachmentDraft], caption: String, chatId: String, replyTo: String?) async throws(MaxlyError) {
        if let attachmentError { throw attachmentError }
        attachmentSends.append(AttachmentSend(drafts: drafts, caption: caption, replyTo: replyTo))
    }

    func cancelUpload(messageId: String) async { cancelledUploads.append(messageId) }
    func set(attachmentError: MaxlyError?) { self.attachmentError = attachmentError }

    nonisolated func uploadProgress() -> AsyncStream<[String: Double]> {
        AsyncStream { continuation in
            Task { await self.addProgress(continuation) }
        }
    }

    private func addProgress(_ continuation: AsyncStream<[String: Double]>.Continuation) {
        progressContinuations.append(continuation)
    }

    var progressSubscribers: Int { progressContinuations.count }

    private var failureContinuations: [AsyncStream<UploadFailure>.Continuation] = []

    nonisolated func uploadFailures() -> AsyncStream<UploadFailure> {
        AsyncStream { continuation in
            Task { await self.addFailure(continuation) }
        }
    }

    private func addFailure(_ continuation: AsyncStream<UploadFailure>.Continuation) {
        failureContinuations.append(continuation)
    }

    var failureSubscribers: Int { failureContinuations.count }

    func publish(failure: UploadFailure) {
        failureContinuations.forEach { $0.yield(failure) }
    }

    func publish(progress: [String: Double]) {
        progressContinuations.forEach { $0.yield(progress) }
    }
    func set(latestError: MaxlyError?) { self.latestError = latestError }
}

func chat(_ id: String, at seconds: TimeInterval, unread: Int = 0, title: String = "Чат", preview: String? = "Привет", type: ChatType = .group) -> Chat {
    Chat(
        id: id,
        title: title,
        type: type,
        lastMessageId: preview == nil ? nil : "m-\(id)",
        unreadCount: unread,
        updatedAt: Date(timeIntervalSince1970: seconds),
        preview: preview
    )
}
