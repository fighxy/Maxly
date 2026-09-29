import Foundation
import OrbitlDomain
@testable import OrbitlData

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

    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        if let fetchGate { await fetchGate.wait() }
        let older = history
            .filter { message in
                message.chatId == chatId && (before.map { message.timestamp < $0 } ?? true)
            }
            .sorted { $0.timestamp > $1.timestamp }
        return .success(Array(older.prefix(limit)))
    }

    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        let index = min(sendCalls, sendResults.count - 1)
        sendCalls += 1
        return sendResults[index]
    }

    func markRead(chatId: String, messageId: String?) async -> Result<Void, MaxAPIError> {
        markReadCalls.append(chatId)
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
        title: "Команда Orbitl",
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
