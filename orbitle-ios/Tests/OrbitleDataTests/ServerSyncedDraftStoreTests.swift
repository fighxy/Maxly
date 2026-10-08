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

    @Test("Черновик с другого устройства новее — встаёт на устройство, экран узнаёт об этом")
    func remoteDraft() async {
        let core = FakeMaxCore()
        let device = DeviceDrafts()
        await device.put("старый", chatId: "-7", at: Date(timeIntervalSince1970: 2))
        let store = ServerSyncedDraftStore(local: device, core: core, replies: .memory())
        let changes = await store.draftChanges()
        await store.serverDraftChanged(chatId: "-7", draft: CoreDraft(chatId: "-7", text: "с телефона", replyTo: "5", updateTime: 8_000))
        #expect(await device.texts["-7"] == "с телефона")
        #expect(await store.draftReply(chatId: "-7") == "5")
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() == "-7")
    }

    @Test("Черновик стёрли на сервере: устройство стирает свой, если он не новее")
    func remoteDiscard() async {
        let core = FakeMaxCore()
        await core.setServerDrafts([CoreDraft(chatId: "-7", text: "было", updateTime: 1_000)])
        let device = DeviceDrafts()
        await device.put("было", chatId: "-7", at: Date(timeIntervalSince1970: 0.5))
        await device.put("своё", chatId: "-8", at: Date(timeIntervalSince1970: 3))
        let store = ServerSyncedDraftStore(local: device, core: core, replies: .memory())
        #expect(await store.draft(chatId: "-7") == "было")
        await core.setServerDrafts([])
        await store.serverDraftChanged(chatId: "-7", draft: nil)
        await store.serverDraftChanged(chatId: "-8", draft: nil)
        #expect(await device.texts["-7"] == nil)
        #expect(await device.texts["-8"] == "своё")
        await store.commitDraft(chatId: "-7")
        #expect(await core.draftCalls.isEmpty)
    }
}
