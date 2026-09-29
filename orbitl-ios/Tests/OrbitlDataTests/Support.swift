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

    func fetchChats() async -> Result<[ChatRecord], MaxAPIError> {
        .success([])
    }

    func fetchMessages(chatId: String, before: Date?, limit: Int) async -> Result<[MessageRecord], MaxAPIError> {
        let older = history
            .filter { $0.chatId == chatId && (before.map { cursor in $0.timestamp < cursor } ?? true) }
            .sorted { $0.timestamp > $1.timestamp }
        return .success(Array(older.prefix(limit)))
    }

    func sendMessage(chatId: String, text: String, clientId: String) async -> Result<SentMessage, MaxAPIError> {
        let index = min(sendCalls, sendResults.count - 1)
        sendCalls += 1
        return sendResults[index]
    }

    func markRead(chatId: String) async -> Result<Void, MaxAPIError> {
        .success(())
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
    ChatRecord(id: id, title: "Команда Orbitl", type: .group, lastMessageId: "m99", unreadCount: 3, updatedAt: Date(timeIntervalSince1970: 100))
}
