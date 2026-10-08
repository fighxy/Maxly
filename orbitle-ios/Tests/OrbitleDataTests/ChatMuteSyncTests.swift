import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Звук чатов из событий ядра: `chatMute` (пуш 134, свой запрос, вход) и `config`.
@Suite("Звук чатов из событий ядра")
struct ChatMuteSyncTests {
    private struct Parts {
        let api: FakeMaxAPI
        let chats: ChatRepositoryImpl
        let sync: SyncEngine
    }

    private func makeParts() async throws -> Parts {
        let api = FakeMaxAPI()
        let stack = try SwiftDataStack(inMemory: true)
        let chats = ChatRepositoryImpl.make(stack: stack, api: api)
        let messages = MessageRepositoryImpl.make(stack: stack, api: api)
        let outbox = OutboxQueue(api: api, sleep: { _ in })
        await messages.attach(outbox: outbox)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        await sync.connectOutgoing()
        await messages.setCurrentUser(id: "me")
        return Parts(api: api, chats: chats, sync: sync)
    }

    private func muteEvent(_ chatId: String, _ muted: Int, until: Int64 = 0) -> CoreEvent {
        CoreEvent(kind: .chatMute, chatId: chatId, messageId: "", authorId: "", text: "", title: "", chatType: "", timeMs: until, unread: -1, muted: muted)
    }

    private func isMuted(_ chats: ChatRepositoryImpl, _ id: String) async -> Bool? {
        for await list in chats.chats() {
            return list.first { $0.id == id }?.isMuted
        }
        return nil
    }

    @Test("chatMute 1 и 0 сразу меняют строку, -1 оставляет прежнюю метку")
    func appliesKnownSkipsUnknown() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a")])
        await parts.sync.consume(muteEvent("a", 1, until: -1))
        #expect(await isMuted(parts.chats, "a") == true)
        await parts.sync.consume(muteEvent("a", -1))
        #expect(await isMuted(parts.chats, "a") == true)
        await parts.sync.consume(muteEvent("a", 0))
        #expect(await isMuted(parts.chats, "a") == false)
        await parts.sync.consume(muteEvent("missing", 1, until: -1))
        #expect(await isMuted(parts.chats, "missing") == nil)
    }

    @Test("Событие свежее ответа списка, запрошенного до него")
    func eventBeatsStaleList() async throws {
        let parts = try await makeParts()
        var stale = makeChat(id: "a")
        stale.isMuted = false
        try await parts.chats.upsert([stale])
        await parts.api.setChats([stale])
        let gate = Gate()
        await parts.api.setFetchGate(gate)
        let refresh = Task { try await parts.chats.refresh() }
        #expect(await eventually { await gate.arrivals == 1 })
        await parts.sync.consume(muteEvent("a", 1, until: -1))
        await gate.open()
        try await refresh.value
        #expect(await isMuted(parts.chats, "a") == true)
    }

    @Test("config перечитывает звук известных чатов, неизвестный не трогает")
    func configReloadsKnownChats() async throws {
        let parts = try await makeParts()
        var muted = makeChat(id: "b")
        muted.isMuted = true
        try await parts.chats.upsert([makeChat(id: "a"), muted, makeChat(id: "c")])
        await parts.api.setMuteState(ChatMuteState(muted: 1, untilMs: -1), chatId: "a")
        await parts.api.setMuteState(ChatMuteState(muted: 0), chatId: "b")
        await parts.sync.consume(CoreEvent(kind: .config, chatId: "", messageId: "", authorId: "", text: "", title: "", chatType: "", timeMs: 0, unread: -1))
        #expect(await isMuted(parts.chats, "a") == true)
        #expect(await isMuted(parts.chats, "b") == false)
        #expect(await isMuted(parts.chats, "c") == false)
        #expect(Set(await parts.api.muteReads) == ["a", "b", "c"])
    }

    @Test("Временное выключение звука кончается само: событие об этом не приходит")
    func timedMuteExpires() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a")])
        let until = Int64((Date().timeIntervalSince1970 + 0.3) * 1000)
        await parts.sync.consume(muteEvent("a", 1, until: until))
        #expect(await isMuted(parts.chats, "a") == true)
        #expect(await eventually { await isMuted(parts.chats, "a") == false })
        #expect(await parts.api.muteReads == ["a"])
    }

    @Test("Новое событие отменяет таймер прежнего срока")
    func newerEventCancelsExpiry() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a")])
        let soon = Int64((Date().timeIntervalSince1970 + 0.2) * 1000)
        await parts.sync.consume(muteEvent("a", 1, until: soon))
        await parts.sync.consume(muteEvent("a", 1, until: -1))
        try await Task.sleep(for: .milliseconds(500))
        #expect(await isMuted(parts.chats, "a") == true)
        #expect(await parts.api.muteReads.isEmpty)
    }

    @Test("MaxAPIClient: звук из ядра, неизвестный срок — 0")
    func clientMapsCoreMute() async {
        let core = FakeMaxCore()
        await core.setMute(chatId: "a", code: 1, until: 1_800_000_000_000)
        let client = MaxAPIClient(core: core)
        #expect(await client.chatMute(chatId: "a") == ChatMuteState(muted: 1, untilMs: 1_800_000_000_000))
        #expect(await client.chatMute(chatId: "b") == ChatMuteState(muted: -1, untilMs: 0))
    }
}
