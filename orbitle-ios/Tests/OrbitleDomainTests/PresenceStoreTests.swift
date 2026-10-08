import Foundation
import Testing
@testable import OrbitleDomain

@Suite("Статус «в сети»")
struct PresenceStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Неизвестное не затирает известное, пустой id не пишется")
    func unknownKeepsKnown() async {
        let store = PresenceStore()
        await store.record(["5": .lastSeen(t0), "": .online], at: t0)
        await store.record(.unknown, userId: "5", at: t0.addingTimeInterval(10))
        #expect(await store.presence(of: "5", now: t0) == .lastSeen(t0))
        #expect(await store.presence(of: "", now: t0) == nil)
        #expect(await store.presence(of: "6", now: t0) == nil)
    }

    @Test("Запоздавшая запись старше известной не применяется")
    func staleRecordIgnored() async {
        let store = PresenceStore()
        await store.record(.online, userId: "5", at: t0)
        await store.record(.lastSeen(t0.addingTimeInterval(-600)), userId: "5", at: t0.addingTimeInterval(-60))
        #expect(await store.isOnline("5", now: t0))
    }

    @Test("«В сети» без подтверждения дольше срока — «был(а)» во время последнего подтверждения")
    func onlineExpires() async {
        let store = PresenceStore(onlineTTL: 300)
        await store.record(.online, userId: "5", at: t0)
        #expect(await store.presence(of: "5", now: t0.addingTimeInterval(299)) == .online)
        #expect(await store.presence(of: "5", now: t0.addingTimeInterval(301)) == .lastSeen(t0))
        #expect(await store.isOnline("5", now: t0.addingTimeInterval(301)) == false)
        await store.record(.online, userId: "5", at: t0.addingTimeInterval(400))
        #expect(await store.isOnline("5", now: t0.addingTimeInterval(500)))
    }

    @Test("Подписчики получают id изменившихся, повтор того же статуса молчит; выход стирает всё")
    func changesAndReset() async {
        let store = PresenceStore()
        var changes = store.changes().makeAsyncIterator()
        // Подписка регистрируется в акторе асинхронно: ждём, пока она дойдёт.
        try? await Task.sleep(for: .milliseconds(50))
        await store.record(["5": .online, "6": .lastSeen(t0)], at: t0)
        let first = await changes.next()
        #expect(first == ["5", "6"])
        await store.record(["5": .online, "7": .online], at: t0.addingTimeInterval(1))
        let second = await changes.next()
        #expect(second == ["7"])
        await store.removeAll()
        #expect(await store.presence(of: "5", now: t0) == nil)
    }
}
