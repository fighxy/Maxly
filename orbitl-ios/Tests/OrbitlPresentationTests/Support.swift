import Foundation
import OrbitlDomain
@testable import OrbitlPresentation

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
    var requestError: OrbitlError?
    var resendError: OrbitlError?
    var verifyError: OrbitlError?
    var passwordError: OrbitlError?
    var registerError: OrbitlError?
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

    func requestCode(phone: String) async throws(OrbitlError) {
        calls.append("code \(phone)")
        try await pass(requestError)
        continuation.yield(.codeSent(codeLength: codeLength))
    }

    func resendCode() async throws(OrbitlError) {
        calls.append("resend")
        try await pass(resendError)
        continuation.yield(.codeSent(codeLength: codeLength))
    }

    func verifyCode(_ code: String) async throws(OrbitlError) {
        calls.append("verify \(code)")
        try await pass(verifyError)
        continuation.yield(afterVerify)
    }

    func submitPassword(_ password: String) async throws(OrbitlError) {
        calls.append("password \(password)")
        try await pass(passwordError)
        continuation.yield(afterPassword)
    }

    func register(firstName: String, lastName: String) async throws(OrbitlError) {
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
    func set(requestError: OrbitlError?) { self.requestError = requestError }
    func set(verifyError: OrbitlError?) { self.verifyError = verifyError }
    func set(passwordError: OrbitlError?) { self.passwordError = passwordError }
    func set(registerError: OrbitlError?) { self.registerError = registerError }
    func set(gate: Gate?) { self.gate = gate }

    /// Как у настоящей сессии: ответ из отменённой попытки бросает `cancelled`.
    private func pass(_ error: OrbitlError?) async throws(OrbitlError) {
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
    nonisolated let typingStream: AsyncStream<[String: [String]]>
    nonisolated let typingContinuation: AsyncStream<[String: [String]]>.Continuation
    nonisolated let capabilities: ChatListCapabilities

    var refreshError: OrbitlError?
    var markError: OrbitlError?
    var actionError: OrbitlError?
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
        let typing = AsyncStream.makeStream(of: [String: [String]].self)
        typingStream = typing.stream
        typingContinuation = typing.continuation
        self.capabilities = capabilities
    }

    nonisolated func chats() -> AsyncStream<[Chat]> { stream }
    nonisolated func emit(_ chats: [Chat]) { continuation.yield(chats) }
    nonisolated func folders() -> AsyncStream<[ChatFolder]> { folderStream }
    nonisolated func emit(folders: [ChatFolder]) { folderContinuation.yield(folders) }
    nonisolated func typing() -> AsyncStream<[String: [String]]> { typingStream }
    nonisolated func emit(typing: [String: [String]]) { typingContinuation.yield(typing) }

    func refresh() async throws(OrbitlError) {
        refreshCount += 1
        if let refreshGate { await refreshGate.wait() }
        if let refreshError { throw refreshError }
    }

    func refresh(chatId: String) async throws(OrbitlError) {}

    func markAsRead(chatId: String) async throws(OrbitlError) {
        marked.append(chatId)
        if let markError { throw markError }
    }

    func setPinned(_ pinned: Bool, chatId: String) async throws(OrbitlError) {
        try await record("\(pinned ? "pin" : "unpin") \(chatId)")
    }

    func reorderPinned(_ chatIds: [String]) async throws(OrbitlError) {
        try await record("order \(chatIds.joined(separator: ","))")
    }

    func setMarkedUnread(_ unread: Bool, chatId: String) async throws(OrbitlError) {
        try await record("\(unread ? "unread" : "read-mark") \(chatId)")
    }

    func setMuted(_ muted: Bool, chatId: String) async throws(OrbitlError) {
        try await record("\(muted ? "mute" : "unmute") \(chatId)")
    }

    func setArchived(_ archived: Bool, chatId: String) async throws(OrbitlError) {
        try await record("\(archived ? "archive" : "unarchive") \(chatId)")
    }

    func delete(chatId: String, forEveryone: Bool) async throws(OrbitlError) {
        try await record("delete \(chatId) \(forEveryone)")
    }

    func loadMoreChats() async throws(OrbitlError) -> Bool {
        pageLoads += 1
        return morePages
    }

    func search(query: String) async throws(OrbitlError) -> [ChatSearchResult] {
        searches.append(query)
        return searchResults
    }

    private func record(_ action: String) async throws(OrbitlError) {
        actions.append(action)
        if let actionGate { await actionGate.wait() }
        if let actionError { throw actionError }
    }

    func set(refreshError: OrbitlError?) { self.refreshError = refreshError }
    func set(markError: OrbitlError?) { self.markError = markError }
    func set(actionError: OrbitlError?) { self.actionError = actionError }
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
    private(set) var saves = 0

    init(_ drafts: [String: String] = [:]) { self.drafts = drafts }

    func draft(chatId: String) async -> String? { drafts[chatId] }
    func saveDraft(_ text: String, chatId: String) async {
        saves += 1
        drafts[chatId] = text.isEmpty ? nil : text
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
    var sendError: OrbitlError?
    private(set) var sent: [String] = []

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(OrbitlError) {}
    func loadMore(chatId: String, before: Date?) async throws(OrbitlError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(OrbitlError) {}

    func send(text: String, chatId: String) async throws(OrbitlError) {
        sent.append(text)
        if let sendError { throw sendError }
    }

    func retry(messageId: String) async throws(OrbitlError) {}
    func set(sendError: OrbitlError?) { self.sendError = sendError }
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
