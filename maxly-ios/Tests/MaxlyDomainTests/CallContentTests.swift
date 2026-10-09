import Testing
@testable import MaxlyDomain

@Suite("Звонок в ленте: исход")
struct CallContentTests {
    private func call(_ hangup: String, ms: Int64, video: Bool = false, link: String? = nil) -> CallContent {
        CallContent(id: "c", durationMs: ms, callType: video ? .video : .audio, hangupType: hangup, joinLink: link)
    }

    @Test("Состоявшийся разговор: HUNGUP с длительностью")
    func connected() {
        let item = call("HUNGUP", ms: 42_000)
        #expect(item.isConnected)
        #expect(item.outcome(outgoing: true) == .answered)
        #expect(item.outcome(outgoing: false) == .answered)
        #expect(!item.isMissed(outgoing: false))
        #expect(!item.isMissed(outgoing: true))
    }

    @Test("Входящий без разговора — пропущенный при MISSED, REJECTED, CANCELED и нулевой длительности")
    func incomingMissed() {
        for hangup in ["MISSED", "REJECTED", "CANCELED"] {
            let item = call(hangup, ms: 0)
            #expect(!item.isConnected)
            #expect(item.outcome(outgoing: false) == .missed)
            #expect(item.isMissed(outgoing: false))
        }
        // Длительность не спасает: исход по hangupType.
        #expect(call("MISSED", ms: 5_000).isMissed(outgoing: false))
        // HUNGUP с нулевой длительностью — разговора не было.
        #expect(call("HUNGUP", ms: 0).isMissed(outgoing: false))
        #expect(call("", ms: 0).isMissed(outgoing: false))
    }

    @Test("Свой без разговора — отменённый, REJECTED — собеседник отклонил; пропущенным не бывает")
    func outgoingNotConnected() {
        #expect(call("CANCELED", ms: 0).outcome(outgoing: true) == .cancelled)
        #expect(call("MISSED", ms: 0).outcome(outgoing: true) == .cancelled)
        #expect(call("HUNGUP", ms: 0).outcome(outgoing: true) == .cancelled)
        #expect(call("REJECTED", ms: 0).outcome(outgoing: true) == .declined)
        #expect(!call("MISSED", ms: 0).isMissed(outgoing: true))
    }

    @Test("Незнакомый hangupType с длительностью — разговор был; регистр не важен")
    func unknownAndCase() {
        let unknown = call("SOMETHING_NEW", ms: 3_000)
        #expect(unknown.hangup == .unknown)
        #expect(unknown.hangupType == "SOMETHING_NEW")
        #expect(unknown.isConnected)
        #expect(call("missed", ms: 0).hangup == .missed)
    }

    @Test("Групповой — по ссылке для входа, пустая ссылка не в счёт; видео — по callType")
    func groupAndVideo() {
        #expect(call("HUNGUP", ms: 1, link: "https://call.example/j/abc").isGroup)
        #expect(!call("HUNGUP", ms: 1, link: "").isGroup)
        #expect(!call("HUNGUP", ms: 1).isGroup)
        #expect(call("HUNGUP", ms: 1, video: true).isVideo)
    }

    @Test("Вложение звонка: доступ, вид для списка и цитата")
    func attachment() {
        let one = MessageContent(attachments: [.call(call("HUNGUP", ms: 1_000))])
        #expect(one.call?.durationMs == 1_000)
        #expect(one.calls.count == 1)
        #expect(one.previewMedia == .call)
        let group = MessageContent(attachments: [.call(call("HUNGUP", ms: 1_000, link: "https://call.example/j/x"))])
        #expect(group.previewMedia == .groupCall)
        let message = Message(id: "1", chatId: "c", authorId: "a", text: "", timestamp: .now, status: .sent, content: group)
        #expect(message.replySnippet == "Групповой звонок")
        // Звонок не файл: путь к локальной копии его не меняет.
        #expect(one.settingLocalPath("/tmp/x", attachmentId: "c") == one)
    }
}
