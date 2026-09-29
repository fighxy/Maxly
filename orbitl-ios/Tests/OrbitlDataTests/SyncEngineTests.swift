import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlData

@Suite("Синхронизация: сеть")
struct SyncNetworkTests {
    @Test("Сеть пропала, пока уходила очередь: опрос не включается")
    func lostWhileFlushing() async throws {
        let api = FakeMaxAPI()
        await api.setSendResults([.failure(.offline)])
        let (messages, outbox) = try await makeMessageStack(api: api)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        try await messages.send(text: "Ждёт сети", chatId: "c1")

        let gate = Gate()
        await api.setSendGate(gate)
        await api.setSendResults([.success(SentMessage(serverId: "srv-1", timestamp: .now))])
        let online = Task { await sync.networkBecameAvailable() }
        #expect(await eventually { await gate.arrivals == 1 })
        await sync.networkLost()
        await gate.open()
        await online.value

        #expect(await sync.isPolling == false)
        #expect(await messages.pendingOutgoing().isEmpty)
    }

    @Test("Сеть есть: очередь уходит и включается опрос, потеря сети его выключает")
    func onlineThenLost() async throws {
        let api = FakeMaxAPI()
        let (messages, outbox) = try await makeMessageStack(api: api)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        await sync.networkBecameAvailable()
        #expect(await sync.isPolling)
        await sync.networkLost()
        #expect(await sync.isPolling == false)
    }
}

@Suite("Синхронизация: пуши")
struct SyncPushTests {
    @Test("stopEvents возвращается, только когда начатый пуш записан целиком")
    func stopWaitsForInFlightPush() async throws {
        let api = FakeMaxAPI()
        await api.setChats([makeChat(id: "c9")])
        let gate = Gate()
        await api.setFetchGate(gate)
        let (messages, outbox) = try await makeMessageStack(api: api)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        let core = FakeMaxCore(livePushes: true)
        await sync.startEvents(core)

        // Сообщение в неизвестный чат: движок подтягивает строку чата и ждёт сервер.
        core.pushes?.yield(CoreEvent(
            kind: .message, chatId: "c9", messageId: "m1", authorId: "bob", text: "Привет",
            title: "", chatType: "", timeMs: 1_000, unread: -1
        ))
        #expect(await eventually { await gate.arrivals == 1 })
        let stop = Task { await sync.stopEvents() }
        await gate.open()
        await stop.value
        #expect(await snapshot(chats).map(\.id) == ["c9"])
    }

    @Test("stopEvents без начатых пушей возвращается сразу")
    func stopWhenIdle() async throws {
        let api = FakeMaxAPI()
        let (messages, outbox) = try await makeMessageStack(api: api)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        await sync.startEvents(FakeMaxCore(livePushes: true))
        await sync.stopEvents()
        await sync.stopEvents()
    }
}
