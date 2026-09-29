import Foundation
import Testing
@testable import OrbitlData

@Suite("Пагинация")
struct PaginationTests {
    @Test("100 сообщений в кэше читаются двумя страницами по 50")
    func localPages() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert(makeHistory(chatId: "c1", count: 100))

        let first = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(first.count == 50)
        #expect(first.first?.id == "m99")
        #expect(first.last?.id == "m50")

        let second = try await repository.loadMore(chatId: "c1", before: first.last?.timestamp)
        #expect(second.count == 50)
        #expect(second.first?.id == "m49")
        #expect(second.last?.id == "m0")

        let third = try await repository.loadMore(chatId: "c1", before: second.last?.timestamp)
        #expect(third.isEmpty)
    }

    @Test("Если кэша не хватает, страница догружается с сервера")
    func serverFallback() async throws {
        let api = FakeMaxAPI()
        let history = makeHistory(chatId: "c1", count: 100)
        await api.setHistory(history)
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert(Array(history.suffix(50)))

        let cached = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(cached.count == 50)

        let older = try await repository.loadMore(chatId: "c1", before: cached.last?.timestamp)
        #expect(older.count == 50)
        #expect(older.first?.id == "m49")
        #expect(older.last?.id == "m0")
    }
}

@Suite("Оптимистичная отправка")
struct OptimisticSendTests {
    @Test("Без сети сообщение остаётся sending, после появления сети становится sent")
    func sendingThenSent() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.offline)])
        let (repository, outbox) = try await makeMessageStack(api: api)

        try await repository.send(text: "Привет", chatId: "c1")
        let pending = await repository.pendingOutgoing()
        #expect(pending.count == 1)
        #expect(pending.first?.status == .sending)
        let localId = try #require(pending.first?.id)

        await api.setSendResults([.success(SentMessage(serverId: "srv-42", timestamp: .now))])
        await outbox.process()

        let stored = try await repository.page(chatId: "c1", before: nil)
        #expect(stored.first?.id == localId)
        #expect(stored.first?.status == .sent)
        let serverId = await repository.serverId(of: localId)
        #expect(serverId == "srv-42")
        #expect(await repository.pendingOutgoing().isEmpty)
    }
}

@Suite("Очередь исходящих")
struct OutboxQueueTests {
    @Test("Временные ошибки повторяются, после успеха очередь пуста")
    func retryThenClear() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([
            .failure(.server(code: "500")),
            .failure(.server(code: "503")),
            .success(SentMessage(serverId: "srv-1", timestamp: .now)),
        ])
        let (repository, outbox) = try await makeMessageStack(api: api)

        try await repository.send(text: "Раз", chatId: "c1")

        #expect(await api.sendCalls == 3)
        #expect(await outbox.pendingCount == 0)
        #expect(await repository.pendingOutgoing().isEmpty)
        let stored = try await repository.page(chatId: "c1", before: nil)
        #expect(stored.first?.status == .sent)
    }

    @Test("После исчерпания попыток сообщение становится failed и уходит из очереди")
    func exhaustedAttempts() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.server(code: "500"))])
        let (repository, outbox) = try await makeMessageStack(api: api)

        try await repository.send(text: "Два", chatId: "c1")

        #expect(await api.sendCalls == OutboxQueue.RetryPolicy().maxAttempts)
        #expect(await outbox.pendingCount == 0)
        let stored = try await repository.page(chatId: "c1", before: nil)
        #expect(stored.first?.status == .failed)
    }

    @Test("Задержка растёт экспоненциально и ограничена сверху")
    func backoff() {
        let policy = OutboxQueue.RetryPolicy(maxAttempts: 10, baseDelay: .seconds(1), maxDelay: .seconds(30))
        #expect(policy.delay(afterAttempt: 1) == .seconds(1))
        #expect(policy.delay(afterAttempt: 2) == .seconds(2))
        #expect(policy.delay(afterAttempt: 4) == .seconds(8))
        #expect(policy.delay(afterAttempt: 8) == .seconds(30))
    }
}
