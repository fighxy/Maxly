import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

actor FakeMaxCore: MaxCore {
    var phase: CorePhase = .idle
    var userId = ""
    var storedToken = false
    var startPhase: CorePhase = .ready
    var startError: CoreFailure?
    var chats: [CoreChat] = []
    var history: [CoreMessage] = []
    var historyBefore: Int64 = -1
    var sent = CoreMessage(id: "srv-1", chatId: "c1", authorId: "me", text: "ok", timeMs: 5_000)
    var sendError: CoreFailure?
    var loadError: CoreFailure?
    var code = CoreCode(token: "code-token", codeLength: 6)
    var authStep: CoreAuthStep = .loggedIn(userId: "u1")
    var authError: CoreFailure?
    var verifyGate: Gate?
    var verifyError: CoreFailure?
    var logoutError: CoreFailure?
    var contactList: [CoreContact] = []
    var callLog: [CoreCall] = []
    var directoryError: CoreFailure?
    private(set) var marked: [String] = []
    private(set) var didLogout = false
    private(set) var lastText = ""
    private(set) var requestedPhones: [String] = []
    private(set) var resendCount = 0
    private(set) var verifiedCodes: [String] = []
    private(set) var registeredNames: [String] = []
    /// Пуши, которые шлёт тест. `nil`: поток событий сразу закрыт.
    nonisolated let pushes: AsyncStream<CoreEvent>.Continuation?
    private nonisolated let pushStream: AsyncStream<CoreEvent>?

    func loadContacts() async throws -> [CoreContact] {
        if let directoryError { throw directoryError }
        return contactList
    }

    // Реакции (docs/reactions.md).
    var reactionReply = ""
    var reactionError: CoreFailure?
    private(set) var reactionCalls: [String] = []
    var reactionsById: [String: String] = [:]
    var reactionUserList: [ReactionUser] = []

    func setReaction(chatId: String, messageId: String, postId: String, emoji: String) async throws -> String {
        reactionCalls.append("\(chatId)/\(messageId)/\(postId)/\(emoji)")
        if let reactionError { throw reactionError }
        return reactionReply
    }

    func loadReactions(chatId: String, messageIds: [String]) async throws -> [String: String] {
        if let reactionError { throw reactionError }
        return reactionsById.filter { messageIds.contains($0.key) }
    }

    func loadReactionCatalog() async throws -> [String] { ["👍", "🔥"] }

    func loadReactionUsers(chatId: String, messageId: String) async throws -> [ReactionUser] {
        if let reactionError { throw reactionError }
        return reactionUserList
    }

    func setReactions(reply: String = "", error: CoreFailure? = nil, byId: [String: String] = [:], users: [ReactionUser] = []) {
        reactionReply = reply
        reactionError = error
        reactionsById = byId
        reactionUserList = users
    }

    func loadCallHistory() async throws -> [CoreCall] {
        if let directoryError { throw directoryError }
        return callLog
    }

    // Настройки аккаунта (docs/settings.md).
    nonisolated let folderList: [ServerFolder] = [
        ServerFolder(id: "all.chat.folder", title: "Все", isAllChats: true),
        ServerFolder(id: "w", title: "Работа", chatIds: ["g"], filters: ["2"]),
    ]
    var sessionList: [DeviceSession] = []

    nonisolated func folders() -> AsyncStream<[ServerFolder]> {
        let list = folderList
        return AsyncStream { $0.yield(list); $0.finish() }
    }

    func loadSessions() async throws -> [DeviceSession] { sessionList }

    func setSessions(_ list: [DeviceSession]) { sessionList = list }

    func startEmailChange(password: String) async throws -> String {
        guard password == "ok" else { throw CoreFailure(kind: "AUTH", key: "error.password.invalid") }
        return "track-1"
    }

    func setDirectory(contacts: [CoreContact] = [], calls: [CoreCall] = [], error: CoreFailure? = nil) {
        contactList = contacts
        callLog = calls
        directoryError = error
    }

    init(livePushes: Bool = false) {
        if livePushes {
            let pair = AsyncStream.makeStream(of: CoreEvent.self)
            pushStream = pair.stream
            pushes = pair.continuation
        } else {
            pushStream = nil
            pushes = nil
        }
    }

    func phaseName() async -> CorePhase { phase }
    func currentUserId() async -> String { userId }
    func hasStoredToken() async -> Bool { storedToken }

    func start() async throws -> CorePhase {
        if let startError { throw startError }
        phase = startPhase
        return startPhase
    }

    func requestCode(phone: String, resend: Bool) async throws -> CoreCode {
        if let authError { throw authError }
        requestedPhones.append(phone)
        if resend { resendCount += 1 }
        return code
    }

    func verifyCode(token: String, code: String) async throws -> CoreAuthStep {
        verifiedCodes.append(code)
        if let verifyGate { await verifyGate.wait() }
        if let error = verifyError ?? authError { throw error }
        return authStep
    }

    func checkPassword(trackId: String, password: String) async throws -> CoreAuthStep {
        if let authError { throw authError }
        return authStep
    }

    func register(token: String, firstName: String, lastName: String) async throws -> CoreAuthStep {
        if let authError { throw authError }
        registeredNames.append("\(firstName)|\(lastName)")
        return authStep
    }

    func logout() async throws {
        didLogout = true
        if let logoutError { throw logoutError }
    }
    func loadChats() async throws -> [CoreChat] {
        if let loadError { throw loadError }
        return chats
    }

    func loadChat(id: String) async throws -> CoreChat {
        if let chat = chats.first(where: { $0.id == id }) { return chat }
        throw CoreFailure(kind: "NOT_FOUND", key: nil)
    }

    func loadHistory(chatId: String, beforeMs: Int64, limit: Int) async throws -> [CoreMessage] {
        historyBefore = beforeMs
        return Array(history.prefix(limit))
    }

    func sendText(chatId: String, text: String) async throws -> CoreMessage {
        if let sendError { throw sendError }
        lastText = text
        return sent
    }

    func markRead(chatId: String, messageId: String) async throws {
        marked.append(messageId)
    }

    nonisolated func phases() -> AsyncStream<CorePhase> {
        AsyncStream { $0.finish() }
    }

    nonisolated func events() -> AsyncStream<CoreEvent> {
        pushStream ?? AsyncStream { $0.finish() }
    }

    /// Закреплённые чаты ядра: как `StateFlow`, новый подписчик сразу получает текущий список.
    nonisolated let pins = PinBox()
    var pinError: CoreFailure?
    private(set) var pinRequests: [[String]] = []

    func setPinError(_ error: CoreFailure?) { pinError = error }

    func setPinnedChats(_ chatIds: [String]) async throws -> [String] {
        pinRequests.append(chatIds)
        if let pinError { throw pinError }
        pins.publish(chatIds)
        return chatIds
    }

    nonisolated func pinnedChats() -> AsyncStream<[String]> {
        pins.subscribe()
    }
}

/// Текущий список закреплённых и подписчики фейкового ядра.
final class PinBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: [String]?
    private var subscribers: [UUID: AsyncStream<[String]>.Continuation] = [:]

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return subscribers.count
    }

    /// Новый список: вход, свой запрос или изменение с другого устройства.
    func publish(_ ids: [String]) {
        lock.lock()
        current = ids
        let targets = Array(subscribers.values)
        lock.unlock()
        targets.forEach { $0.yield(ids) }
    }

    func subscribe() -> AsyncStream<[String]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
        let id = UUID()
        lock.lock()
        subscribers[id] = continuation
        let value = current
        lock.unlock()
        if let value { continuation.yield(value) }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.subscribers[id] = nil
            self.lock.unlock()
        }
        return stream
    }
}

actor FakeMedia: MediaRepository {
    private(set) var clearCount = 0
    /// Следующая очистка кэша ждёт, пока тест не откроет задвижку.
    private var clearGate: Gate?

    func holdNextClear(_ gate: Gate) { clearGate = gate }

    func preview(for item: MediaItem) async throws(OrbitleError) -> URL {
        throw .networkUnavailable
    }

    nonisolated func download(_ item: MediaItem) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func clearCache() async {
        clearCount += 1
        if let gate = clearGate {
            clearGate = nil
            await gate.wait()
        }
    }
}

struct SessionParts: Sendable {
    var core: FakeMaxCore
    var api: FakeMaxAPI
    var stack: SwiftDataStack
    var chats: ChatRepositoryImpl
    var messages: MessageRepositoryImpl
    var sync: SyncEngine
    var media: FakeMedia
    var session: SessionManager
    var defaults: UserDefaults
    var suite: String
}

func makeSession() async throws -> SessionParts {
    let core = FakeMaxCore()
    let api = FakeMaxAPI()
    let stack = try SwiftDataStack(inMemory: true)
    let chats = ChatRepositoryImpl.make(stack: stack, api: api)
    let messages = MessageRepositoryImpl.make(stack: stack, api: api)
    let outbox = OutboxQueue(api: api, sleep: { _ in })
    await messages.attach(outbox: outbox)
    let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
    await sync.connectOutgoing()
    let media = FakeMedia()
    let suite = "orbitle.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let session = SessionManager(
        core: core,
        stack: stack,
        chats: chats,
        messages: messages,
        sync: sync,
        media: media,
        defaults: defaults
    )
    return SessionParts(
        core: core,
        api: api,
        stack: stack,
        chats: chats,
        messages: messages,
        sync: sync,
        media: media,
        session: session,
        defaults: defaults,
        suite: suite
    )
}

func withSession(_ body: (SessionParts) async throws -> Void) async throws {
    let parts = try await makeSession()
    defer { parts.defaults.removePersistentDomain(forName: parts.suite) }
    try await body(parts)
}

func snapshot(_ chats: ChatRepositoryImpl) async -> [Chat] {
    let stream = chats.chats()
    for await page in stream { return page }
    return []
}

func phase(of session: SessionManager) async -> AuthPhase {
    let stream = session.phases()
    for await value in stream { return value }
    return .restoring
}

func isSuccess(_ result: Result<Void, MaxAPIError>) -> Bool {
    if case .success = result { return true }
    return false
}

@Suite("Ядро и маппинг")
struct CoreMappingTests {
    @Test("Миллисекунды Unix переживают круг через Date")
    func unixMillis() {
        let date = Date(unixMillis: 1_700_000_000_123)
        #expect(date.unixMillis == 1_700_000_000_123)
    }

    @Test("Чат из ядра: тип, пустой заголовок и пустое превью")
    func chatRecord() {
        let dialog = CoreMapping.chat(CoreChat(
            id: "1", title: "", type: "DIALOG", lastMessageId: "", lastText: "", updatedAtMs: 1_500, unread: 2
        ))
        #expect(dialog.type == .private)
        #expect(dialog.title == "")
        #expect(dialog.lastMessageId == nil)
        #expect(dialog.preview == nil)
        #expect(dialog.unreadCount == 2)
        #expect(dialog.updatedAt == Date(timeIntervalSince1970: 1.5))

        let channel = CoreMapping.chat(CoreChat(
            id: "2", title: "Новости", type: "CHANNEL", lastMessageId: "m", lastText: "эфир", updatedAtMs: 0, unread: 0
        ))
        #expect(channel.type == .channel)
        #expect(channel.preview == "эфир")
        #expect(CoreMapping.chat(CoreChat(
            id: "3", title: "Группа", type: "CHAT", lastMessageId: "", lastText: "", updatedAtMs: 0, unread: 0
        )).type == .group)
    }

    @Test("Ошибки ядра становятся категориями API")
    func errors() {
        #expect(CoreMapping.apiError(CoreFailure(kind: "NETWORK", key: nil)) == .offline)
        #expect(CoreMapping.apiError(CoreFailure(kind: "TIMEOUT", key: nil)) == .offline)
        #expect(CoreMapping.apiError(CoreFailure(kind: "CLOSED", key: nil)) == .offline)
        #expect(CoreMapping.apiError(CoreFailure(kind: "CANCELLED", key: nil)) == .cancelled)
        #expect(CoreMapping.apiError(CoreFailure(kind: "SESSION_EXPIRED", key: nil)) == .sessionExpired)
        #expect(CoreMapping.apiError(CoreFailure(kind: "AUTH", key: nil)) == .invalidResponse)
        #expect(CoreMapping.apiError(CoreFailure(kind: "SERVER", key: "proto.bad")) == .server(code: "proto.bad"))
        #expect(CoreMapping.apiError(CoreFailure(kind: "SERVER", key: "")) == .server(code: "SERVER"))
        #expect(CoreMapping.apiError(CoreFailure(kind: "NOT_FOUND", key: nil)) == .invalidResponse)
        #expect(CoreMapping.apiError(CoreFailure(kind: "MALFORMED_REPLY", key: nil)) == .server(code: "MALFORMED_REPLY"))
        #expect(CoreMapping.apiError(CoreFailure(kind: "UNKNOWN", key: nil)) == .unknown)
        #expect(CoreMapping.apiError(URLError(.notConnectedToInternet)) == .offline)
        #expect(CoreMapping.apiError(URLError(.cancelled)) == .cancelled)
        #expect(CoreMapping.apiError(CancellationError()) == .cancelled)
        #expect(!MaxAPIError.cancelled.isRetryable)
        #expect(MaxAPIError.cancelled.orbitleError == .cancelled)
        #expect(MaxAPIError.unknown.orbitleError == .unknown)
        #expect(MaxAPIError.offline.isRetryable)
        #expect(!MaxAPIError.sessionExpired.isRetryable)
        #expect(MaxAPIError.invalidResponse.orbitleError == .invalidRequest)
    }

    @Test("События сообщения и чата")
    func events() {
        let message = MessageRecord(CoreEvent(
            kind: .message, chatId: "c", messageId: "m", authorId: "bob", text: "Привет",
            title: "", chatType: "", timeMs: 5_000, unread: -1
        ))
        #expect(message?.text == "Привет")
        #expect(message?.status == .sent)
        #expect(message?.serverId == "m")
        #expect(MessageRecord(CoreEvent(
            kind: .deleted, chatId: "c", messageId: "m", authorId: "", text: "",
            title: "", chatType: "", timeMs: 0, unread: -1
        )) == nil)

        let chat = ChatRecord(CoreEvent(
            kind: .chat, chatId: "c", messageId: "", authorId: "", text: "",
            title: "Канал", chatType: "CHANNEL", timeMs: 0, unread: -1
        ))
        #expect(chat?.type == .channel)
        #expect(chat?.title == "Канал")
        #expect(chat?.unreadCount == 0)
        #expect(chat?.preview == nil)
    }
}

@Suite("MaxAPIClient")
struct MaxAPIClientTests {
    @Test("Список, история и отправка идут через ядро")
    func mapsCalls() async {
        let core = FakeMaxCore()
        await core.setChats()
        let client = MaxAPIClient(core: core)

        let chats = await client.fetchChats()
        guard case .success(let records) = chats else {
            Issue.record("чаты \(chats)")
            return
        }
        #expect(records.first?.type == .private)
        #expect(records.first?.preview == "Привет")
        #expect(records.first?.updatedAt == Date(unixMillis: 5_000))

        let before = Date(timeIntervalSince1970: 1.5)
        _ = await client.fetchMessages(chatId: "1", before: before, limit: 20)
        #expect(await core.historyBefore == before.unixMillis)

        _ = await client.fetchMessages(chatId: "1", before: nil, limit: 20)
        #expect(await core.historyBefore == 0)

        let sent = await client.sendMessage(chatId: "1", text: "текст", clientId: "local-1")
        guard case .success(let message) = sent else {
            Issue.record("отправка \(sent)")
            return
        }
        #expect(message.serverId == "srv-1")
        #expect(message.timestamp == Date(unixMillis: 5_000))
        #expect(await core.lastText == "текст")
    }

    @Test("Пустой messageId не зовёт ядро, сеть и сессия различаются")
    func markAndErrors() async {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        let skipped = await client.markRead(chatId: "1", messageId: nil)
        let empty = await client.markRead(chatId: "1", messageId: "")
        #expect(isSuccess(skipped))
        #expect(isSuccess(empty))
        #expect(await core.marked.isEmpty)

        let marked = await client.markRead(chatId: "1", messageId: "55")
        #expect(isSuccess(marked))
        #expect(await core.marked == ["55"])

        await core.failSend()
        #expect(await client.sendMessage(chatId: "1", text: "x", clientId: "local") == .failure(.offline))
        await core.failSession()
        #expect(await client.fetchChats() == .failure(.sessionExpired))
        await core.failLoad(kind: "AUTH")
        #expect(await client.fetchChats() == .failure(.invalidResponse))
    }
}

extension FakeMaxCore {
    func setChats() {
        chats = [CoreChat(
            id: "1", title: "Аня", type: "DIALOG", lastMessageId: "m", lastText: "Привет", updatedAtMs: 5_000, unread: 1
        )]
    }

    func failSend() { sendError = CoreFailure(kind: "NETWORK", key: nil) }
    func failSession() { loadError = CoreFailure(kind: "SESSION_EXPIRED", key: nil) }
    func failLoad(kind: String) { loadError = CoreFailure(kind: kind, key: nil) }
    func setUser(_ id: String) { userId = id }
    func setHistory(_ messages: [CoreMessage]) { history = messages }
    func setStoredToken(_ value: Bool) { storedToken = value }
    func setStartPhase(_ phase: CorePhase) { startPhase = phase }
    func setStartError(_ error: CoreFailure?) { startError = error }
    func setAuthStep(_ step: CoreAuthStep) { authStep = step }
    func setAuthError(_ error: CoreFailure?) { authError = error }
    func setVerifyGate(_ gate: Gate?) { verifyGate = gate }
    func setVerifyError(_ error: CoreFailure?) { verifyError = error }
    func setCode(_ value: CoreCode) { code = value }
    func setLogoutError(_ error: CoreFailure?) { logoutError = error }
}

@Suite("Сессия")
struct SessionManagerTests {
    @Test("Готовое ядро показывает чаты и запоминает пользователя")
    func restoreReady() async throws {
        try await withSession { parts in
            await parts.core.setUser("42")
            await parts.core.setStoredToken(true)
            await parts.api.setChats([makeChat()])
            await parts.session.restoreSession()
            #expect(await phase(of: parts.session) == .signedIn(userId: "42"))
            let chats = await snapshot(parts.chats)
            #expect(chats.count == 1)
            #expect(chats.first?.preview == "Последнее")
            #expect(parts.defaults.string(forKey: SessionManager.userDefaultsKey) == "42")
            #expect(await parts.media.clearCount == 0)
        }
    }

    @Test("Отклонённый токен оставляет базу")
    func tokenRejectedKeepsCache() async throws {
        try await withSession { parts in
            try await parts.chats.upsert([makeChat(id: "keep")])
            await parts.core.setStartPhase(.tokenRejected)
            await parts.core.setStoredToken(true)
            await parts.session.restoreSession()
            #expect(await phase(of: parts.session) == .expired)
            let kept = await snapshot(parts.chats)
            #expect(kept.contains(where: { $0.id == "keep" }))
            #expect(await parts.media.clearCount == 0)
            #expect(await parts.core.didLogout == false)
        }
    }

    @Test("Ошибка сети при сохранённом токене показывает кэш")
    func offlineShowsCache() async throws {
        try await withSession { parts in
            parts.defaults.set("u1", forKey: SessionManager.userDefaultsKey)
            try await parts.chats.upsert([makeChat(id: "cached")])
            await parts.core.setStoredToken(true)
            await parts.core.setStartError(CoreFailure(kind: "NETWORK", key: nil))
            await parts.session.restoreSession()
            #expect(await phase(of: parts.session) == .signedIn(userId: "u1"))
            let cached = await snapshot(parts.chats)
            #expect(cached.contains(where: { $0.id == "cached" }))
            #expect(await parts.media.clearCount == 0)
        }
    }

    @Test("Выход стирает чаты, медиа и id")
    func logoutClears() async throws {
        try await withSession { parts in
            await parts.core.setUser("42")
            await parts.api.setChats([makeChat()])
            await parts.session.restoreSession()
            await parts.session.logout()
            #expect(await phase(of: parts.session) == .signedOut)
            #expect(await snapshot(parts.chats).isEmpty)
            #expect(parts.defaults.string(forKey: SessionManager.userDefaultsKey) == nil)
            #expect(await parts.core.didLogout)
            #expect(await parts.media.clearCount == 1)
        }
    }

    @Test("Другой пользователь стирает чужой кэш до загрузки своих чатов")
    func otherUserErases() async throws {
        try await withSession { parts in
            parts.defaults.set("user-a", forKey: SessionManager.userDefaultsKey)
            try await parts.chats.upsert([makeChat(id: "old")])
            await parts.core.setUser("user-b")
            await parts.api.setChats([makeChat(id: "fresh")])
            await parts.session.restoreSession()
            let chats = await snapshot(parts.chats)
            #expect(chats.contains(where: { $0.id == "fresh" }))
            #expect(chats.contains(where: { $0.id == "old" }) == false)
            #expect(parts.defaults.string(forKey: SessionManager.userDefaultsKey) == "user-b")
            #expect(await parts.media.clearCount == 1)
        }
    }

    @Test("Тот же пользователь кэш не стирает")
    func sameUserKeeps() async throws {
        try await withSession { parts in
            parts.defaults.set("u1", forKey: SessionManager.userDefaultsKey)
            try await parts.chats.upsert([makeChat(id: "mine")])
            await parts.core.setUser("u1")
            await parts.session.restoreSession()
            let mine = await snapshot(parts.chats)
            #expect(mine.contains(where: { $0.id == "mine" }))
            #expect(await parts.media.clearCount == 0)
        }
    }

    @Test("Код, пароль и регистрация")
    func authSteps() async throws {
        try await withSession { parts in
            try await parts.session.requestCode(phone: "+79990001122")
            #expect(await phase(of: parts.session) == .codeSent(codeLength: 6))

            await parts.core.setAuthStep(.password(trackId: "track", hint: "смс"))
            try await parts.session.verifyCode("1234")
            #expect(await phase(of: parts.session) == .password(hint: "смс"))

            await parts.core.setAuthStep(.register(token: "reg"))
            try await parts.session.submitPassword("secret")
            #expect(await phase(of: parts.session) == .registration)

            await parts.core.setAuthStep(.loggedIn(userId: "7"))
            await parts.core.setUser("7")
            try await parts.session.register(firstName: "Иван", lastName: "К")
            #expect(await phase(of: parts.session) == .signedIn(userId: "7"))
        }
    }

    @Test("Повтор кода без номера и сеть на запросе кода")
    func codeErrors() async throws {
        try await withSession { parts in
            do {
                try await parts.session.resendCode()
                Issue.record("повтор без номера")
            } catch let error as OrbitleError {
                #expect(error == .invalidRequest)
            } catch {
                Issue.record("повтор \(error)")
            }
            await parts.core.setAuthError(CoreFailure(kind: "NETWORK", key: nil))
            do {
                try await parts.session.requestCode(phone: "+7")
                Issue.record("сеть")
            } catch let error as OrbitleError {
                #expect(error == .networkUnavailable)
            } catch {
                Issue.record("сеть \(error)")
            }
        }
    }
}

@Suite("События синхронизации")
struct SyncEventTests {
    @Test("Входящее «Привет» пишется в базу и увеличивает непрочитанные")
    func incomingMessage() async throws {
        let api = FakeMaxAPI()
        let stack = try SwiftDataStack(inMemory: true)
        let chats = ChatRepositoryImpl.make(stack: stack, api: api)
        let messages = MessageRepositoryImpl.make(stack: stack, api: api)
        let outbox = OutboxQueue(api: api, sleep: { _ in })
        await messages.attach(outbox: outbox)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        try await chats.upsert([makeChat()])
        await messages.setCurrentUser(id: "me")

        await sync.consume(CoreEvent(
            kind: .message, chatId: "c1", messageId: "m1", authorId: "bob", text: "Привет",
            title: "", chatType: "DIALOG", timeMs: 1_700_000_000_000, unread: -1
        ))
        let page = try await messages.page(chatId: "c1", before: nil)
        #expect(page.first?.text == "Привет")
        #expect(page.first?.authorId == "bob")
        let list = await snapshot(chats)
        #expect(list.first?.preview == "Привет")
        #expect(list.first?.unreadCount == 4)

        await sync.consume(CoreEvent(
            kind: .edited, chatId: "c1", messageId: "m1", authorId: "bob", text: "Новый",
            title: "", chatType: "DIALOG", timeMs: 1_700_000_000_000, unread: -1
        ))
        #expect(try await messages.page(chatId: "c1", before: nil).first?.text == "Новый")
        #expect(await snapshot(chats).first?.unreadCount == 4)

        await sync.consume(CoreEvent(
            kind: .message, chatId: "c1", messageId: "m2", authorId: "me", text: "своё",
            title: "", chatType: "DIALOG", timeMs: 1_700_000_000_500, unread: -1
        ))
        #expect(await snapshot(chats).first?.unreadCount == 4)

        await sync.consume(CoreEvent(
            kind: .read, chatId: "c1", messageId: "", authorId: "me", text: "",
            title: "", chatType: "", timeMs: 1_700_000_000_500, unread: 0
        ))
        #expect(await snapshot(chats).first?.unreadCount == 0)

        await sync.consume(CoreEvent(
            kind: .deleted, chatId: "c1", messageId: "m1", authorId: "", text: "",
            title: "", chatType: "", timeMs: 0, unread: -1
        ))
        let left = try await messages.page(chatId: "c1", before: nil)
        #expect(left.contains(where: { $0.id == "m1" }) == false)
        #expect(left.contains(where: { $0.text == "своё" }))
    }
}

@Suite("Медиакэш")
struct MediaCacheTests {
    @Test("Вытесняет самый давно использованный файл")
    func evictsOldest() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "orbitle-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let older = directory.appending(path: "older")
        let newer = directory.appending(path: "newer")
        try Data(count: 100).write(to: older)
        try Data(count: 100).write(to: newer)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 20)], ofItemAtPath: newer.path)
        try MediaCache.evict(directory: directory, limit: 150)
        #expect(!FileManager.default.fileExists(atPath: older.path))
        #expect(FileManager.default.fileExists(atPath: newer.path))
    }
}
