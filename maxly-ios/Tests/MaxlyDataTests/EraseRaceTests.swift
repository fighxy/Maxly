import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Ответы после очистки базы")
struct EraseRaceTests {
    @Test("Список чатов, запрошенный до очистки, в базу не пишется")
    func lateChatListDropped() async throws {
        let api = FakeMaxAPI()
        await api.setChats([makeChat()])
        let gate = Gate()
        await api.setFetchGate(gate)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)

        let refresh = Task { await failure { try await chats.refresh() } }
        #expect(await eventually { await gate.arrivals == 1 })
        try await chats.removeAll()
        await gate.open()

        #expect(await refresh.value == .cancelled)
        #expect(await snapshot(chats).isEmpty)
    }

    @Test("Один чат, запрошенный до очистки, в базу не пишется")
    func lateChatDropped() async throws {
        let api = FakeMaxAPI()
        await api.setChats([makeChat()])
        let gate = Gate()
        await api.setFetchGate(gate)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)

        let refresh = Task { await failure { try await chats.refresh(chatId: "c1") } }
        #expect(await eventually { await gate.arrivals == 1 })
        try await chats.removeAll()
        await gate.open()

        #expect(await refresh.value == .cancelled)
        #expect(await snapshot(chats).isEmpty)
    }

    @Test("История, запрошенная до очистки, в базу не пишется")
    func lateHistoryDropped() async throws {
        let api = FakeMaxAPI()
        await api.setHistory(makeHistory(chatId: "c1", count: 10))
        let gate = Gate()
        await api.setFetchGate(gate)
        let (messages, _) = try await makeMessageStack(api: api)

        let latest = Task { await failure { try await messages.fetchLatest(chatId: "c1") } }
        #expect(await eventually { await gate.arrivals == 1 })
        try await messages.removeAll()
        await gate.open()
        #expect(await latest.value == .cancelled)
        #expect(try await messages.page(chatId: "c1", before: nil).isEmpty)

        let older = Task { await failure { _ = try await messages.loadMore(chatId: "c1", before: nil) } }
        #expect(await eventually { await gate.arrivals == 2 })
        #expect(await older.value == nil)
        #expect(try await messages.page(chatId: "c1", before: nil).count == 10)
    }
}
