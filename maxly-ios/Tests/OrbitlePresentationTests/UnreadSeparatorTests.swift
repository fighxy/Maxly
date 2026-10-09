import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Разделитель непрочитанных")
struct UnreadSeparatorTests {
    private func message(_ id: String, author: String) -> Message {
        Message(id: id, chatId: "c", authorId: author, text: id, timestamp: Date(timeIntervalSince1970: Double(id)!), status: .sent)
    }

    @Test("Над первым из N последних чужих сообщений; свои не считаются")
    func anchor() {
        let feed = [message("1", author: "bob"), message("2", author: "bob"), message("3", author: "me"), message("4", author: "bob")]
        #expect(TranscriptLayout.unreadAnchor(feed, unread: 1, currentUserId: "me", complete: true) == "4")
        #expect(TranscriptLayout.unreadAnchor(feed, unread: 2, currentUserId: "me", complete: true) == "2")
        #expect(TranscriptLayout.unreadAnchor(feed, unread: 0, currentUserId: "me", complete: true) == nil)
    }

    @Test("Ленты не хватает: после сверки — самое старое чужое, до неё — ждём")
    func shortFeed() {
        let feed = [message("1", author: "bob"), message("2", author: "bob")]
        #expect(TranscriptLayout.unreadAnchor(feed, unread: 5, currentUserId: "me", complete: true) == "1")
        #expect(TranscriptLayout.unreadAnchor(feed, unread: 5, currentUserId: "me", complete: false) == nil)
    }

    @Test("По своей отметке: над первым чужим новее неё, а не по счётчику")
    func byOwnMark() {
        let feed = (1...6).map { message("\($0)", author: $0 == 5 ? "me" : "bob") }
        // Отметка на 2-м (2 000 мс): первое чужое новее — 3-е, хотя счётчик говорит 1.
        #expect(TranscriptLayout.firstUnread(feed, readMark: 2_000, unread: 1, currentUserId: "me", complete: true) == "3")
        // Отметка на 4-м: своё 5-е пропускается, первое чужое новее — 6-е.
        #expect(TranscriptLayout.firstUnread(feed, readMark: 4_000, unread: 3, currentUserId: "me", complete: true) == "6")
        // Без непрочитанных разделителя нет, какой бы ни была отметка.
        #expect(TranscriptLayout.firstUnread(feed, readMark: 2_000, unread: 0, currentUserId: "me", complete: true) == nil)
    }

    @Test("Отметки нет, она раньше ленты или после неё нет чужих — по счётчику")
    func ownMarkFallsBackToCount() {
        let feed = (10...12).map { message("\($0)", author: "bob") }
        #expect(TranscriptLayout.firstUnread(feed, readMark: 0, unread: 2, currentUserId: "me", complete: true) == "11")
        // Отметка старше всей ленты: где граница, не видно.
        #expect(TranscriptLayout.firstUnread(feed, readMark: 5_000, unread: 2, currentUserId: "me", complete: true) == "11")
        // Отметка на последнем: новее чужих нет.
        #expect(TranscriptLayout.firstUnread(feed, readMark: 12_000, unread: 1, currentUserId: "me", complete: true) == "12")
    }

    @Test("Строка с якорем помечена, остальные нет")
    func rows() {
        let feed = [message("1", author: "bob"), message("2", author: "bob")]
        let rows = TranscriptLayout.rows(feed, currentUserId: "me", unreadAnchorId: "2")
        #expect(rows.map(\.startsUnread) == [false, true])
    }

    @Test("Кнопка OPEN_APP без бота и параметра; CLIPBOARD копирует payload")
    func buttonActions() {
        #expect(InlineButton(type: "open_app", text: "App").action == .openApp(botId: nil, startParam: nil))
        let scoped = InlineButton(type: "OPEN_APP", text: "App", webApp: "https://max.ru/bot?startapp=x&chat_id=-42", contactId: "9")
        #expect(scoped.action == .openApp(botId: "9", startParam: "x", chatId: "-42"))
        #expect(InlineButton(type: "CLIPBOARD", text: "Код", payload: "1234").action == .copy("1234"))
        #expect(InlineButton(type: "REQUEST_CONTACT", text: "?").action == .callback)
    }
}
