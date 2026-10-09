import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Часы, которые тест двигает сам.
private final class PresenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_790_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@Suite("Статусы через ядро")
struct CorePresenceTests {
    @Test("Коды ядра превращаются в статусы фикстур")
    func codes() {
        #expect(CorePresence(userId: "1", status: -1).presence == .unknown)
        #expect(CorePresence(userId: "1", status: 0).presence == .unknown)
        #expect(CorePresence(userId: "1", status: 1).presence == .online)
        #expect(CorePresence(userId: "1", status: 2).presence == .recently)
        #expect(CorePresence(userId: "1", status: 3).presence == .longAgo)
        #expect(CorePresence(userId: "1", status: 0, seenMs: 1_790_000_000_000).presence
            == .lastSeen(Date(timeIntervalSince1970: 1_790_000_000)))
    }

    @Test("Видимые люди спрашиваются пачкой, повтор — не раньше чем через минуту")
    func refresh() async {
        let core = FakeMaxCore()
        await core.setPresence(answer: [CorePresence(userId: "2", status: 1), CorePresence(userId: "3", status: 3)])
        let store = PresenceStore()
        let clock = PresenceClock()
        let service = CorePresenceService(core: core, store: store, now: { clock.now })

        await service.refresh(["2", "3", "2", "", "-5abc"])
        #expect(await core.presenceRequests == [["2", "3"]])
        #expect(await store.presence(of: "2", now: clock.now) == .online)
        #expect(await service.presence(of: "3") == .longAgo)

        clock.advance(30)
        await service.refresh(["2", "3"])
        #expect(await core.presenceRequests.count == 1)

        clock.advance(31)
        await service.refresh(["3"])
        #expect(await core.presenceRequests == [["2", "3"], ["3"]])
    }

    @Test("Ошибка не мешает спросить снова; пустое хранилище спрашивает ядро")
    func errorAndFallback() async {
        let core = FakeMaxCore()
        await core.setPresence(answer: [], held: ["7": CorePresence(userId: "7", status: 2)], error: CoreFailure(kind: "NETWORK", key: "offline"))
        let store = PresenceStore()
        let service = CorePresenceService(core: core, store: store)

        await service.refresh(["7"])
        await service.refresh(["7"])
        #expect(await core.presenceRequests == [["7"], ["7"]])
        #expect(await service.presence(of: "7") == .recently)
        #expect(await store.presence(of: "7") == .recently)
        #expect(await service.presence(of: "8") == nil)
    }

    @Test("Событие presence пишет статус в общее хранилище")
    func event() async throws {
        let api = FakeMaxAPI()
        let stack = try SwiftDataStack(inMemory: true)
        let chats = ChatRepositoryImpl.make(stack: stack, api: api)
        let messages = MessageRepositoryImpl.make(stack: stack, api: api)
        let outbox = OutboxQueue(api: api, sleep: { _ in })
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        let store = PresenceStore()
        await sync.attachPresence(store)

        await sync.consume(CoreEvent(
            kind: .presence, chatId: "", messageId: "", authorId: "42", text: "",
            title: "", chatType: "", timeMs: 0, unread: -1, presence: 1
        ))
        #expect(await store.presence(of: "42") == .online)

        let seen = Date().addingTimeInterval(-600)
        await sync.consume(CoreEvent(
            kind: .presence, chatId: "", messageId: "", authorId: "42", text: "",
            title: "", chatType: "", timeMs: Int64(seen.timeIntervalSince1970 * 1000), unread: -1, presence: 0
        ))
        if case .lastSeen = await store.presence(of: "42") {} else { Issue.record("ожидался «был в …»") }
    }
}
