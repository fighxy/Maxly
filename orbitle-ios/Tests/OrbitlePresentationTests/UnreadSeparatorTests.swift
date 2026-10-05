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

    @Test("Строка с якорем помечена, остальные нет")
    func rows() {
        let feed = [message("1", author: "bob"), message("2", author: "bob")]
        let rows = TranscriptLayout.rows(feed, currentUserId: "me", unreadAnchorId: "2")
        #expect(rows.map(\.startsUnread) == [false, true])
    }

    @Test("Кнопка OPEN_APP без бота и параметра; CLIPBOARD копирует payload")
    func buttonActions() {
        #expect(InlineButton(type: "open_app", text: "App").action == .openApp(botId: nil, startParam: nil))
        #expect(InlineButton(type: "CLIPBOARD", text: "Код", payload: "1234").action == .copy("1234"))
        #expect(InlineButton(type: "REQUEST_CONTACT", text: "?").action == .callback)
    }
}
