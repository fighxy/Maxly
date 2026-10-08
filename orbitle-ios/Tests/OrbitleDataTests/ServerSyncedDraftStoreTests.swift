import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Черновики устройства в памяти: текст и время записи.
private actor DeviceDrafts: ChatDraftStore {
    private(set) var texts: [String: String] = [:]
    private var times: [String: Date] = [:]
    var now = Date(timeIntervalSince1970: 5)

    func put(_ text: String, chatId: String, at date: Date) {
        texts[chatId] = text
        times[chatId] = date
    }

    func draft(chatId: String) async -> String? { texts[chatId] }

    func saveDraft(_ text: String, chatId: String) async {
        texts[chatId] = text.isEmpty ? nil : text
        times[chatId] = text.isEmpty ? nil : now
    }

    func draftTime(chatId: String) async -> Date? { times[chatId] }
}

@Suite("Черновики: устройство и сервер")
struct ServerSyncedDraftStoreTests {
    @Test("При открытии побеждает более новый черновик сервера и записывается на устройство")
    func serverWins() async {
        let core = FakeMaxCore()
        await core.setServerDrafts([CoreDraft(chatId: "-7", text: "с ноутбука", updateTime: 8_000)])
        let device = DeviceDrafts()
        await device.put("старый", chatId: "-7", at: Date(timeIntervalSince1970: 2))
        let store = ServerSyncedDraftStore(local: device, core: core, replies: .memory(), now: { Date(timeIntervalSince1970: 6) })
        #expect(await store.draft(chatId: "-7") == "с ноутбука")
        #expect(await device.texts["-7"] == "с ноутбука")
    }

    @Test("Черновик устройства новее — остаётся")
    func deviceWins() async {
        let core = FakeMaxCore()
        await core.setServerDrafts([CoreDraft(chatId: "-7", text: "старый", updateTime: 1_000)])
        let device = DeviceDrafts()
        await device.put("свежий", chatId: "-7", at: Date(timeIntervalSince1970: 3))
        let store = ServerSyncedDraftStore(local: device, core: core, replies: .memory(), now: { Date(timeIntervalSince1970: 6) })
        #expect(await store.draft(chatId: "-7") == "свежий")
    }

    @Test("Ушли из чата: новый текст сохраняется, тот же — нет, пустой стирает черновик сервера")
    func commit() async {
        let core = FakeMaxCore()
        await core.setServerDrafts([CoreDraft(chatId: "-7", text: "было", updateTime: 1_000)])
        let device = DeviceDrafts()
        let store = ServerSyncedDraftStore(local: device, core: core, replies: .memory(), now: { Date(timeIntervalSince1970: 6) })
        await store.saveDraft("стало", chatId: "-7")
        #expect(await core.draftCalls.isEmpty)
        await store.commitDraft(chatId: "-7")
        await store.commitDraft(chatId: "-7")
        await store.saveDraft("", chatId: "-7")
        await store.commitDraft(chatId: "-7")
        #expect(await core.draftCalls == ["save -7 стало", "discard -7 9000"])
    }

    @Test("«Избранное» на сервер не уходит")
    func savedStaysLocal() async {
        let core = FakeMaxCore()
        let store = ServerSyncedDraftStore(local: DeviceDrafts(), core: core, replies: .memory())
        await store.saveDraft("себе", chatId: Chat.savedMessagesId)
        await store.commitDraft(chatId: Chat.savedMessagesId)
        #expect(await core.draftCalls.isEmpty)
    }

    @Test("Черновик из одного ответа сохраняется на сервере и возвращается с сервера")
    func replyOnly() async {
        let core = FakeMaxCore()
        let store = ServerSyncedDraftStore(local: DeviceDrafts(), core: core, replies: .memory(), now: { Date(timeIntervalSince1970: 6) })
        await store.saveDraftReply("12", chatId: "-7")
        await store.commitDraft(chatId: "-7")
        #expect(await core.draftCalls == ["save -7  ↩12"])

        let other = FakeMaxCore()
        await other.setServerDrafts([CoreDraft(chatId: "-7", text: "", replyTo: "44", updateTime: 8_000)])
        let device = DeviceDrafts()
        let fresh = ServerSyncedDraftStore(local: device, core: other, replies: .memory())
        #expect(await fresh.draft(chatId: "-7") == nil)
        #expect(await fresh.draftReply(chatId: "-7") == "44")
    }

    @Test("После отправки черновик сервера стирается один раз")
    func discardAfterSend() async {
        let core = FakeMaxCore()
        await core.setServerDrafts([CoreDraft(chatId: "-7", text: "было", updateTime: 1_000)])
        let store = ServerSyncedDraftStore(local: DeviceDrafts(), core: core, replies: .memory())
        await store.messageSent(chatId: "-7")
        await store.messageSent(chatId: "-7")
        await store.commitDraft(chatId: "-7")
        #expect(await core.draftCalls == ["discard -7 1000"])
        #expect(await store.draft(chatId: "-7") == nil)
    }
}
