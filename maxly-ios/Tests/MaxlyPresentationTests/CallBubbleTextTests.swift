import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Звонок в ленте: подписи")
struct CallBubbleTextTests {
    private func call(_ hangup: String, ms: Int64, video: Bool = false, link: String? = nil) -> CallContent {
        CallContent(id: "c", durationMs: ms, callType: video ? .video : .audio, hangupType: hangup, joinLink: link)
    }

    @Test("Заголовок по направлению и исходу, как во вкладке «Звонки»")
    func titles() {
        #expect(CallBubbleText.title(call("HUNGUP", ms: 1_000), outgoing: true) == "Исходящий звонок")
        #expect(CallBubbleText.title(call("HUNGUP", ms: 1_000), outgoing: false) == "Входящий звонок")
        #expect(CallBubbleText.title(call("HUNGUP", ms: 1_000, video: true), outgoing: false) == "Входящий видеозвонок")
        #expect(CallBubbleText.title(call("MISSED", ms: 0), outgoing: false) == "Пропущенный звонок")
        #expect(CallBubbleText.title(call("REJECTED", ms: 0, video: true), outgoing: false) == "Пропущенный видеозвонок")
        #expect(CallBubbleText.title(call("CANCELED", ms: 0), outgoing: true) == "Отменённый звонок")
        #expect(CallBubbleText.title(call("REJECTED", ms: 0), outgoing: true) == "Отклонённый звонок")
        #expect(CallBubbleText.title(call("HUNGUP", ms: 1_000, link: "https://call.example/j/x"), outgoing: true) == "Групповой звонок")
        #expect(CallBubbleText.title(call("MISSED", ms: 0, video: true, link: "https://call.example/j/x"), outgoing: false) == "Групповой видеозвонок")
    }

    @Test("Длительность только у состоявшегося, из миллисекунд, с часами от часа")
    func duration() {
        #expect(CallBubbleText.duration(call("HUNGUP", ms: 42_000)) == "0:42")
        #expect(CallBubbleText.duration(call("HUNGUP", ms: 725_999)) == "12:05")
        #expect(CallBubbleText.duration(call("HUNGUP", ms: 3_723_000)) == "1:02:03")
        // 9 секунд — это 9000 мс, а не 9000 секунд: без эвристик по величине.
        #expect(CallBubbleText.duration(call("HUNGUP", ms: 9_000)) == "0:09")
        #expect(CallBubbleText.duration(call("MISSED", ms: 0)) == nil)
        #expect(CallBubbleText.duration(call("CANCELED", ms: 4_000)) == nil)
    }

    @Test("Красным — только пропущенный входящий; значок по исходу")
    func alertAndSymbol() {
        #expect(CallBubbleText.isAlert(call("MISSED", ms: 0), outgoing: false))
        #expect(!CallBubbleText.isAlert(call("CANCELED", ms: 0), outgoing: true))
        #expect(!CallBubbleText.isAlert(call("HUNGUP", ms: 1_000), outgoing: false))
        #expect(CallBubbleText.symbol(call("HUNGUP", ms: 1_000), outgoing: true) == "phone.arrow.up.right.fill")
        #expect(CallBubbleText.symbol(call("HUNGUP", ms: 1_000), outgoing: false) == "phone.arrow.down.left.fill")
        #expect(CallBubbleText.symbol(call("MISSED", ms: 0), outgoing: false) == "phone.down.fill")
        #expect(CallBubbleText.symbol(call("MISSED", ms: 0, video: true), outgoing: false) == "video.slash.fill")
        #expect(CallBubbleText.symbol(call("HUNGUP", ms: 1_000, video: true), outgoing: false) == "video.fill")
    }

    @Test("VoiceOver: заголовок, длительность, время")
    func accessibility() {
        #expect(CallBubbleText.accessibility(call("HUNGUP", ms: 42_000), outgoing: true, time: "12:30")
            == "Исходящий звонок, длительность 0:42, 12:30")
        #expect(CallBubbleText.accessibility(call("MISSED", ms: 0), outgoing: false, time: "")
            == "Пропущенный звонок")
    }

    @Test("Строка списка: «Звонок» и «Групповой звонок»")
    func listLabels() {
        #expect(ChatListFormatter.mediaLabel(.call) == "Звонок")
        #expect(ChatListFormatter.mediaLabel(.groupCall) == "Групповой звонок")
        #expect(MessageMediaKind(rawValue: "groupCall") == .groupCall)
    }
}

@Suite("Звонок в ленте: приватный режим")
struct CallPrivateModeTests {
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    let now = Date(timeIntervalSince1970: 1_790_683_200)

    private func chat(media: MessageMediaKind, outgoing: Bool = false) -> Chat {
        Chat(
            id: "9",
            title: "Аня Петрова",
            type: .private,
            lastMessageId: "m1",
            unreadCount: 0,
            updatedAt: now.addingTimeInterval(-60),
            preview: "",
            lastMessage: ChatLastMessage(authorName: "Аня", isOutgoing: outgoing, media: media)
        )
    }

    @Test("Строка списка: звонок остаётся «Звонком», без имени и направления")
    func listRow() {
        let item = formatter.item(for: chat(media: .call), now: now)
        #expect(item.preview == "Звонок")
        let masked = PrivateModeMask.item(item)
        #expect(masked.preview == "Звонок")
        #expect(masked.title == "Личный чат")
        #expect(PrivateModeMask.item(formatter.item(for: chat(media: .groupCall, outgoing: true), now: now)).preview == "Групповой звонок")
    }

    @Test("Пузырь: «Звонок» вместо «Вы получили сообщение», без исхода и длительности")
    func bubble() {
        let missed = CallContent(id: "c", durationMs: 0, hangupType: "MISSED")
        let message = Message(id: "1", chatId: "9", authorId: "a", text: "", timestamp: now, status: .sent,
                              content: MessageContent(attachments: [.call(missed)]))
        let masked = PrivateModeMask.message(message, outgoing: false)
        #expect(masked.text == "Звонок")
        #expect(masked.content == .empty)
        #expect(PrivateModeMask.messageText(for: message, outgoing: false) == "Звонок")
        let plain = Message(id: "2", chatId: "9", authorId: "a", text: "Привет", timestamp: now, status: .sent)
        #expect(PrivateModeMask.messageText(for: plain, outgoing: true) == "Вы отправили сообщение")
    }
}
