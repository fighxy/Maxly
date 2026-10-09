import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Пометка «непрочитано» с сообщения")
@MainActor
struct MarkUnreadTests {
    @Test("Открытый чат перестаёт быть открытым, и ответ сервера не отмечает его прочитанным")
    func leavesTheChat() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1, unread: 0)])
        #expect(await eventually { model.items.count == 1 })
        await model.open(chatId: "a")
        let gate = Gate()
        await repository.set(actionGate: gate)
        let task = Task { await model.markUnread(chatId: "a", from: Date(timeIntervalSince1970: 50)) }
        #expect(await eventually { model.openChatId == nil })
        // Сервер ещё отвечает, а база уже прислала непрочитанное — прочтение не уходит.
        repository.emit([chat("a", at: 1, unread: 2)])
        #expect(await eventually { model.items.first?.unreadBadge == "2" })
        await gate.open()
        #expect(await task.value)
        #expect(await repository.actions == ["unread-from a 50"])
        #expect(await repository.marked.isEmpty)
    }

    @Test("Ошибка сервера возвращает чат в открытые и показывается")
    func failureKeepsTheChatOpen() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1, unread: 0)])
        #expect(await eventually { model.items.count == 1 })
        await model.open(chatId: "a")
        await repository.set(actionError: .networkUnavailable)
        #expect(await model.markUnread(chatId: "a", from: Date(timeIntervalSince1970: 50)) == false)
        #expect(model.openChatId == "a")
        #expect(model.error == .networkUnavailable)
    }

    @Test("Пункт есть у сообщений с сервера, кроме отправляемых и служебных о закрепе")
    func whichMessages() {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository())
        let sent = Message(id: "10", chatId: "c", authorId: "u", text: "x", timestamp: .now, status: .sent)
        let local = Message(id: "local-1", chatId: "c", authorId: "me", text: "x", timestamp: .now, status: .sending)
        let pinNotice = Message(
            id: "11", chatId: "c", authorId: "u", text: "", timestamp: .now, status: .sent,
            content: MessageContent(pin: PinNotice(messageId: "10", preview: "x"))
        )
        #expect(model.canMarkUnread(sent))
        #expect(!model.canMarkUnread(local))
        #expect(!model.canMarkUnread(pinNotice))

        model.requestMarkUnread(local)
        #expect(model.unreadMarkCandidate == nil)
        model.requestMarkUnread(sent)
        #expect(model.unreadMarkCandidate?.id == "10")
    }
}
