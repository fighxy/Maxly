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

    var refreshError: OrbitlError?
    var markError: OrbitlError?
    var refreshGate: Gate?
    private(set) var refreshCount = 0
    private(set) var marked: [String] = []

    init() {
        let pair = AsyncStream.makeStream(of: [Chat].self)
        stream = pair.stream
        continuation = pair.continuation
    }

    nonisolated func chats() -> AsyncStream<[Chat]> { stream }
    nonisolated func emit(_ chats: [Chat]) { continuation.yield(chats) }

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

    func set(refreshError: OrbitlError?) { self.refreshError = refreshError }
    func set(markError: OrbitlError?) { self.markError = markError }
    func set(refreshGate: Gate?) { self.refreshGate = refreshGate }
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
