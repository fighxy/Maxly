import Foundation
import Testing
@testable import MaxlyDomain

@Suite("Журнал звонков по курсору")
struct CallLogTests {
    private let me = "100"

    private func item(
        _ id: String, caller: String = "200", chat: String = "", hangup: String = "HUNGUP",
        duration: Int64 = -1, time: Int64 = 1_000, group: String = "", name: String = "", video: Bool = false
    ) -> CallLogItem {
        CallLogItem(
            historyId: id, callId: "call-\(id)", callName: name, callerId: caller, chatId: chat,
            isVideo: video, hangupType: hangup, timeMs: time, durationMs: duration, groupCallType: group
        )
    }

    @Test("Первая страница с пустым курсором, дальше курсор ответа; пустая страница — конец")
    func paging() {
        var log = CallLog()
        #expect(log.sync.isEmpty)
        #expect(log.hasMore)
        let changed1 = log.apply(CallLogPage(sync: "50", items: [item("1"), item("2")]))
        #expect(changed1)
        #expect(log.sync == "50")
        #expect(log.hasMore)
        log.apply(CallLogPage(sync: "60", items: [item("3")]))
        #expect(log.items.count == 3)
        #expect(log.hasMore)
        log.apply(CallLogPage(sync: "60", items: []))
        #expect(!log.hasMore)
        #expect(log.sync == "60")
        // «0» — курсора нет: прежний остаётся.
        log.apply(CallLogPage(sync: "0", items: [item("4")]))
        #expect(log.sync == "60")
        #expect(!log.hasMore)
    }

    @Test("reset заменяет журнал целиком, запись с тем же historyId обновляется")
    func resetAndUpdate() {
        var log = CallLog()
        log.apply(CallLogPage(sync: "1", items: [item("1"), item("2", hangup: "MISSED")]))
        log.apply(CallLogPage(sync: "2", items: [item("2", hangup: "HUNGUP", duration: 5_000)]))
        #expect(log.items["2"]?.durationMs == 5_000)
        let changed2 = log.apply(CallLogPage(sync: "3", reset: true, items: [item("9")]))
        #expect(changed2)
        #expect(Array(log.items.keys) == ["9"])
        // Тот же ответ ещё раз ничего не меняет.
        let changed3 = log.apply(CallLogPage(sync: "4", items: [item("9")]))
        #expect(!changed3)
    }

    @Test("Пуш remove убирает записи, add добавляет; новые сверху")
    func pushes() {
        var log = CallLog()
        log.apply(CallLogPage(sync: "1", items: [item("1", time: 1_000), item("2", time: 3_000), item("3", time: 3_000)]))
        #expect(log.ordered.map(\.historyId) == ["3", "2", "1"])
        let changed4 = log.remove(["2", "nope"])
        #expect(changed4)
        let changed5 = log.remove(["nope"])
        #expect(!changed5)
        let changed6 = log.add([item("10", time: 5_000)])
        #expect(changed6)
        #expect(log.ordered.map(\.historyId) == ["10", "3", "1"])
    }

    @Test("Собеседник: позвонивший, у своего звонка — из id диалога (XOR); у группы — чат")
    func peers() {
        #expect(CallLog.peerId(of: item("1", caller: "200"), me: me) == "200")
        let dialog = CallLog.dialogChatId(me: me, peerId: "200")
        #expect(dialog == String(100 ^ 200))
        #expect(CallLog.peerId(of: item("2", caller: me, chat: dialog), me: me) == "200")
        #expect(CallLog.peerId(of: item("3", caller: me, chat: ""), me: me) == "")
        #expect(CallLog.peerId(of: item("4", caller: "200", chat: "-77", group: "CHAT"), me: me) == "-77")
        #expect(CallLog.peerId(of: item("5", caller: "200", group: "LINK"), me: me) == "")
    }

    @Test("Исход: пропущенный, отклонённый, отменённый, состоявшийся; без длительности — nil")
    func outcomes() {
        let missed = CallLog.record(item("1", hangup: "MISSED"), me: me, peer: nil)
        #expect(missed.isMissed)
        #expect(missed.direction == .incoming)
        #expect(CallLog.record(item("2", hangup: "CANCELED"), me: me, peer: nil).isMissed)
        #expect(CallLog.record(item("3", hangup: "REJECTED"), me: me, peer: nil).outcome == .declined)
        let talked = CallLog.record(item("4", hangup: "HUNGUP", duration: 65_000), me: me, peer: nil)
        #expect(talked.outcome == .answered)
        #expect(talked.duration == 65)
        #expect(CallLog.record(item("5", hangup: "HUNGUP"), me: me, peer: nil).duration == nil)
        #expect(CallLog.record(item("6", hangup: "HUNGUP", duration: 0), me: me, peer: nil).isMissed)

        let declined = CallLog.record(item("7", caller: me, hangup: "REJECTED"), me: me, peer: nil)
        #expect(declined.direction == .outgoing)
        #expect(declined.outcome == .declined)
        #expect(CallLog.record(item("8", caller: me, hangup: "MISSED"), me: me, peer: nil).outcome == .cancelled)
        #expect(CallLog.record(item("9", caller: me, hangup: "", duration: 3_000), me: me, peer: nil).outcome == .answered)
        #expect(CallLog.record(item("10", caller: me, hangup: ""), me: me, peer: nil).outcome == .cancelled)
    }

    @Test("Строка: имя звонка или собеседника, чат диалога, видео, дата")
    func records() {
        let peer = CallLogPeer(name: "Анна", avatarURL: URL(string: "https://a/b.jpg"))
        let outgoing = CallLog.record(item("1", caller: me, time: 1_700_000_000_000, video: true), me: me, peer: peer)
        #expect(outgoing.title == "Анна")
        #expect(outgoing.avatarURL == URL(string: "https://a/b.jpg"))
        #expect(outgoing.chatId == nil)
        #expect(outgoing.isVideo)
        #expect(outgoing.date == Date(timeIntervalSince1970: 1_700_000_000))

        let incoming = CallLog.record(item("2", caller: "200"), me: me, peer: nil)
        #expect(incoming.title == "Звонок")
        #expect(incoming.peerId == "200")
        #expect(incoming.chatId == CallLog.dialogChatId(me: me, peerId: "200"))

        let group = CallLog.record(item("3", caller: "200", chat: "-77", group: "CHAT", name: "Планёрка"), me: me, peer: peer)
        #expect(group.isGroup)
        #expect(group.title == "Планёрка")
        #expect(group.chatId == "-77")
        let link = CallLog.record(item("4", caller: me, group: "LINK"), me: me, peer: nil)
        #expect(link.title == "Групповой звонок")
        #expect(link.chatId == nil)
    }
}
