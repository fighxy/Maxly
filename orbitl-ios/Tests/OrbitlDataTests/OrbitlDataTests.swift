import Foundation
import Testing
import OrbitlDomain
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
        #expect(first.first?.text == "Сообщение 99")
        #expect(first.first?.authorId == "bob")
        #expect(first.first?.timestamp == Date(timeIntervalSince1970: 100))
        #expect(first.last?.id == "m50")
        #expect(first.last?.mediaId == "media50")
        #expect(first.allSatisfy { $0.status == .sent && $0.chatId == "c1" })
        // Страница идёт от новых к старым.
        #expect(zip(first, first.dropFirst()).allSatisfy { $0.timestamp > $1.timestamp })

        let second = try await repository.loadMore(chatId: "c1", before: first.last?.timestamp)
        #expect(second.count == 50)
        #expect(second.first?.id == "m49")
        #expect(second.last?.id == "m0")
        #expect(second.last?.text == "Сообщение 0")
        #expect(second.last?.serverId == "m0")

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

@Suite("Окно истории")
struct HistoryWindowTests {
    private func first(_ stream: AsyncStream<[Message]>) async -> [Message]? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    @Test("loadOlder расширяет окно на страницу и догружает недостающее с сервера")
    func loadOlderGrowsWindow() async throws {
        let api = FakeMaxAPI()
        let history = makeHistory(chatId: "c1", count: 120)
        await api.setHistory(history)
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert(Array(history.suffix(50)))

        let initial = try #require(await first(repository.messages(chatId: "c1")))
        #expect(initial.count == 50)
        #expect(initial.first?.id == "m70")
        #expect(initial.last?.id == "m119")

        try await repository.loadOlder(chatId: "c1")
        let grown = try #require(await first(repository.messages(chatId: "c1")))
        #expect(grown.count == 100)
        #expect(grown.first?.id == "m20")
        #expect(grown.last?.id == "m119")

        try await repository.loadOlder(chatId: "c1")
        let all = try #require(await first(repository.messages(chatId: "c1")))
        #expect(all.count == 120)
        #expect(all.first?.id == "m0")
    }
}

@Suite("Оптимистичная отправка")
struct OptimisticSendTests {
    @Test("Без сети сообщение остаётся sending, после появления сети становится sent")
    func sendingThenSent() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.offline)])
        let (repository, outbox) = try await makeMessageStack(api: api)

        await repository.setCurrentUser(id: "alice")
        try await repository.send(text: "Привет", chatId: "c1")
        let pending = await repository.pendingOutgoing()
        #expect(pending.count == 1)
        #expect(pending.first?.status == .sending)
        #expect(pending.first?.text == "Привет")
        #expect(pending.first?.authorId == "alice")
        #expect(pending.first?.serverId == nil)
        let localId = try #require(pending.first?.id)
        #expect(localId.hasPrefix("local-"))

        await api.setSendResults([.success(SentMessage(serverId: "srv-42", timestamp: .now))])
        await outbox.process()

        let stored = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.id == localId)
        #expect(stored.first?.text == "Привет")
        #expect(stored.first?.status == .sent)
        #expect(stored.first?.serverId == "srv-42")
        #expect(await repository.pendingOutgoing().isEmpty)
    }
}

@Suite("Сопоставление с сервером")
struct ServerMatchTests {
    @Test("Своё отправленное сообщение, пришедшее с сервера, не дублируется")
    func noDuplicateAfterEcho() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.success(SentMessage(serverId: "srv-7", timestamp: Date(timeIntervalSince1970: 500)))])
        let (repository, _) = try await makeMessageStack(api: api)

        try await repository.send(text: "Эхо", chatId: "c1")
        try await repository.upsert([MessageRecord(
            id: "srv-7", serverId: "srv-7", chatId: "c1", authorId: "alice",
            text: "Эхо", timestamp: Date(timeIntervalSince1970: 500), status: .sent
        )])

        let stored = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.serverId == "srv-7")
    }
}

@Suite("Запись пакетом")
struct BatchUpsertTests {
    @Test("Пакет сообщений: новые, известные по id, своё по серверному id и повтор внутри пакета")
    func mixedMessageBatch() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.success(SentMessage(serverId: "srv-1", timestamp: Date(timeIntervalSince1970: 50)))])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.send(text: "своё", chatId: "c1")
        try await repository.upsert([makeHistory(chatId: "c1", count: 1)[0]])

        let inserted = try await repository.upsert([
            MessageRecord(id: "m0", serverId: "m0", chatId: "c1", authorId: "alice", text: "правка", timestamp: Date(timeIntervalSince1970: 1), status: .sent),
            MessageRecord(id: "srv-1", serverId: "srv-1", chatId: "c1", authorId: "me", text: "своё с сервера", timestamp: Date(timeIntervalSince1970: 50), status: .sent),
            MessageRecord(id: "m5", serverId: "m5", chatId: "c1", authorId: "bob", text: "новое", timestamp: Date(timeIntervalSince1970: 60), status: .sent),
            MessageRecord(id: "m5", serverId: "m5", chatId: "c1", authorId: "bob", text: "новое, повтор", timestamp: Date(timeIntervalSince1970: 60), status: .sent),
        ])

        #expect(inserted == ["m5"])
        let stored = try await repository.page(chatId: "c1", before: nil)
        #expect(stored.count == 3)
        #expect(stored.first { $0.id == "m0" }?.text == "правка")
        #expect(stored.first { $0.serverId == "srv-1" }?.id.hasPrefix("local-") == true)
        #expect(stored.first { $0.serverId == "srv-1" }?.text == "своё с сервера")
        #expect(stored.first { $0.id == "m5" }?.text == "новое, повтор")
    }

    @Test("Пакет чатов с повтором одного id даёт одну строку")
    func duplicateChatsInBatch() async throws {
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: FakeMaxAPI())
        try await chats.upsert([
            ChatRecord(id: "a", title: "Первый", type: .group, updatedAt: Date(timeIntervalSince1970: 1)),
            ChatRecord(id: "b", title: "Второй", type: .channel, updatedAt: Date(timeIntervalSince1970: 2)),
            ChatRecord(id: "a", title: "", type: .group, unreadCount: 2, updatedAt: Date(timeIntervalSince1970: 3), preview: "свежее"),
        ])
        let rows = await snapshot(chats)
        #expect(rows.map(\.id) == ["a", "b"])
        #expect(rows.first?.title == "Первый")
        #expect(rows.first?.preview == "свежее")
        #expect(rows.first?.unreadCount == 2)
    }
}

@Suite("Эхо своего сообщения")
struct EchoTests {
    @Test("Эхо, пришедшее раньше ответа на отправку, не дублирует сообщение")
    func echoBeforeResponse() async throws {
        let api = FakeMaxAPI()
        let gate = Gate()
        await api.setSendGate(gate)
        await api.setSendResults([.success(SentMessage(serverId: "srv-7", timestamp: Date(timeIntervalSince1970: 500)))])
        let (repository, _) = try await makeMessageStack(api: api)
        await repository.setCurrentUser(id: "alice")

        let send = Task { await failure { try await repository.send(text: "Эхо", chatId: "c1") } }
        #expect(await eventually { await gate.arrivals == 1 })
        try await repository.upsert([MessageRecord(
            id: "srv-7", serverId: "srv-7", chatId: "c1", authorId: "alice",
            text: "Эхо", timestamp: Date(timeIntervalSince1970: 500), status: .sent
        )])
        await gate.open()
        #expect(await send.value == nil)

        let stored = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.id.hasPrefix("local-") == true)
        #expect(stored.first?.serverId == "srv-7")
        #expect(stored.first?.status == .sent)
    }
}

@Suite("Чаты")
struct ChatRepositoryTests {
    @Test("Поля чата доходят до доменной модели, markAsRead сбрасывает счётчик")
    func chatFields() async throws {
        let stack = try SwiftDataStack(inMemory: true)
        let repository = ChatRepositoryImpl.make(stack: stack, api: FakeMaxAPI())
        try await repository.upsert([makeChat()])

        var iterator = repository.chats().makeAsyncIterator()
        let chats = try #require(await iterator.next())
        let chat = try #require(chats.first)
        #expect(chat.title == "Команда Orbitl")
        #expect(chat.type == .group)
        #expect(chat.unreadCount == 3)
        #expect(chat.lastMessageId == "m99")
        #expect(chat.preview == "Последнее")

        try await repository.markAsRead(chatId: "c1")
        let updated = try #require(await iterator.next())
        #expect(updated.first?.unreadCount == 0)
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
        let stored = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(stored.first?.status == .sent)
        #expect(stored.first?.serverId == "srv-1")
        #expect(stored.first?.text == "Раз")
    }

    @Test("После исчерпания попыток сообщение становится failed и уходит из очереди")
    func exhaustedAttempts() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.server(code: "500"))])
        let (repository, outbox) = try await makeMessageStack(api: api)

        try await repository.send(text: "Два", chatId: "c1")

        #expect(await api.sendCalls == OutboxQueue.RetryPolicy().maxAttempts)
        #expect(await outbox.pendingCount == 0)
        let stored = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(stored.first?.status == .failed)
        #expect(stored.first?.serverId == nil)
        #expect(stored.first?.text == "Два")
    }

    @Test("Повтор неотправленного: failed снова уходит в очередь и становится sent")
    func retryFailed() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.server(code: "500"))])
        let (repository, outbox) = try await makeMessageStack(api: api)
        try await repository.send(text: "Три", chatId: "c1")
        let failed = try #require(try await repository.loadMore(chatId: "c1", before: nil).first)
        #expect(failed.status == .failed)

        await api.setSendResults([.success(SentMessage(serverId: "srv-9", timestamp: .now))])
        try await repository.retry(messageId: failed.id)

        #expect(await outbox.pendingCount == 0)
        let stored = try await repository.loadMore(chatId: "c1", before: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.id == failed.id)
        #expect(stored.first?.status == .sent)
        #expect(stored.first?.serverId == "srv-9")
    }

    @Test("Повтор уже отправленного ничего не делает")
    func retrySentIsNoop() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.send(text: "Четыре", chatId: "c1")
        let sent = try #require(try await repository.loadMore(chatId: "c1", before: nil).first)
        #expect(sent.status == .sent)

        try await repository.retry(messageId: sent.id)

        #expect(await api.sendCalls == 1)
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

@Suite("База")
struct StorageTests {
    @Test("Базы в памяти, созданные параллельно, не мешают друг другу")
    func parallelContainers() async throws {
        try await withThrowingTaskGroup(of: [String].self) { group in
            for index in 0..<16 {
                group.addTask {
                    let stack = try SwiftDataStack(inMemory: true)
                    let chats = ChatRepositoryImpl.make(stack: stack, api: FakeMaxAPI())
                    try await chats.upsert([makeChat(id: "c\(index)")])
                    return await snapshot(chats).map(\.id)
                }
            }
            var seen = Set<String>()
            for try await ids in group {
                #expect(ids.count == 1)
                seen.formUnion(ids)
            }
            #expect(seen.count == 16)
        }
    }
}

@Suite("Подписки")
struct SubscriptionTests {
    @Test("Ушедший подписчик снимается и больше не получает снимки")
    func finishedObserverRemoved() async throws {
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: FakeMaxAPI())
        let reader = Task {
            for await _ in chats.chats() { return }
        }
        await reader.value
        #expect(await eventually { await chats.observerCount == 0 })

        // Поток, брошенный до первого значения, тоже не остаётся в подписчиках.
        let cancelled = Task {
            for await _ in chats.chats() {}
        }
        cancelled.cancel()
        await cancelled.value
        #expect(await eventually { await chats.observerCount == 0 })
    }
}
