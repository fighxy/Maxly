import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Закрепы на «сервере»: запоминает запросы списка 242.
private actor PinMessages: MessageRepository {
    private(set) var updates: [(action: String, ids: [String])] = []

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) -> Bool { false }
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func updatePin(chatId: String, action: String, messageIds: [String], forMe: Bool, notify: Bool) async throws(MaxlyError) {
        updates.append((action, messageIds))
    }
}

/// Служебное сообщение «закрепил» с id закрепа.
private func pinNotice(_ id: String, pinned target: String, preview: String) -> Message {
    Message(
        id: id, chatId: "c", authorId: "bob", text: "",
        timestamp: Date(timeIntervalSince1970: 10), status: .sent,
        content: MessageContent(pin: PinNotice(messageId: target, preview: preview))
    )
}

@Suite("Закрепы чата")
@MainActor
struct ChatPinsModelTests {
    @Test("Пока список не пришёл, шапка берёт закреп из служебного сообщения ленты")
    func noticeFromLive() {
        let model = ChatPinsModel(chatId: "c", repository: PinMessages())
        model.live = { [pinNotice("1", pinned: "42", preview: "Правила")] }
        model.applyState()
        #expect(model.pinned?.id == "42")
        #expect(model.banner?.text == "Правила")
        #expect(model.banner?.counter == nil)
    }

    @Test("Закрепить и открепить: список, счётчик «1 из 2», уведомления")
    func pinAndUnpin() async {
        let repository = PinMessages()
        let model = ChatPinsModel(chatId: "c", repository: repository)
        var notices: [String] = []
        model.onNotice = { notices.append($0) }
        let first = Message(id: "100", chatId: "c", authorId: "me", text: "первое", timestamp: Date(), status: .sent)
        let second = Message(id: "200", chatId: "c", authorId: "me", text: "второе", timestamp: Date(), status: .sent)
        await model.pin(first)
        await model.pin(second)
        #expect(model.fromList)
        #expect(model.banner?.id == "200")
        #expect(model.banner?.counter == "1 из 2")
        await model.unpin(messageId: "200")
        #expect(model.list.pins.map(\.messageId) == ["100"])
        #expect(notices == ["Сообщение закреплено", "Сообщение закреплено", "Закреп снят"])
        #expect(await repository.updates.map(\.action) == ["pin", "pin", "unpin"])
    }

    @Test("Касание плашки ведёт к текущему закрепу и показывает следующий")
    func cycle() async {
        let model = ChatPinsModel(chatId: "c", repository: PinMessages())
        var focused: [String] = []
        model.onFocus = { focused.append($0) }
        await model.pin(Message(id: "1", chatId: "c", authorId: "me", text: "a", timestamp: Date(), status: .sent))
        await model.pin(Message(id: "2", chatId: "c", authorId: "me", text: "b", timestamp: Date(), status: .sent))
        model.cycle()
        model.cycle()
        #expect(focused == ["2", "1"])
    }

    @Test("Пуш «снять все» очищает список")
    func pushUnpinAll() async {
        let hub = PinHub()
        let model = ChatPinsModel(chatId: "c", repository: PinMessages())
        model.attach(hub)
        model.startWatch()
        await model.pin(Message(id: "1", chatId: "c", authorId: "me", text: "a", timestamp: Date(), status: .sent))
        hub.publish(PinPush(chatId: "c", action: "unpinAll", messageId: "", count: 0))
        #expect(await eventually { model.list.pins.isEmpty })
        #expect(model.banner == nil)
        model.stopWatch()
    }
}
