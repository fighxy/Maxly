import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Отложенные на «сервере»: список, правка и отмена; `failure` — ответ на любой запрос.
private actor ScheduledMessages: MessageRepository {
    private(set) var items: [FoundMessage] = []
    private(set) var edits: [(id: String, text: String)] = []
    var failure: MaxlyError?

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) -> Bool { false }
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func schedule(chatId: String, text: String, sendAt: Date) async throws(MaxlyError) {
        if let failure { throw failure }
        items.append(FoundMessage(chatId: chatId, messageId: "s\(items.count + 1)", text: text, date: sendAt))
    }

    func scheduled(chatId: String) async throws(MaxlyError) -> [FoundMessage] {
        if let failure { throw failure }
        return items
    }

    func editScheduled(chatId: String, messageId: String, text: String, sendAt: Date) async throws(MaxlyError) -> FoundMessage {
        if let failure { throw failure }
        edits.append((messageId, text))
        let item = FoundMessage(chatId: chatId, messageId: messageId, text: text, date: sendAt)
        items = items.map { $0.messageId == messageId ? item : $0 }
        return item
    }

    func cancelScheduled(chatId: String, messageIds: [String]) async throws(MaxlyError) {
        if let failure { throw failure }
        items.removeAll { messageIds.contains($0.messageId) }
    }

    func set(failure: MaxlyError?) { self.failure = failure }
}

@Suite("Отложенные сообщения чата")
@MainActor
struct ScheduledMessagesModelTests {
    @Test("Запланировать: поле очищается, уведомление, список по времени отправки")
    func scheduleAndList() async {
        let repository = ScheduledMessages()
        let model = ScheduledMessagesModel(chatId: "c", repository: repository)
        var cleared = 0
        var notices: [String] = []
        model.onScheduled = { cleared += 1 }
        model.onNotice = { notices.append($0) }
        let later = Date(timeIntervalSince1970: 2_000)
        let sooner = Date(timeIntervalSince1970: 1_000)
        await model.schedule(text: "позже", at: later)
        await model.schedule(text: "раньше", at: sooner)
        #expect(cleared == 2)
        #expect(notices == ["Сообщение запланировано", "Сообщение запланировано"])
        #expect(model.items.map(\.text) == ["раньше", "позже"])
    }

    @Test("Правка, «отправить сейчас» и отмена; пустой текст не уходит")
    func editSendNowCancel() async {
        let repository = ScheduledMessages()
        let model = ScheduledMessagesModel(chatId: "c", repository: repository)
        await model.schedule(text: "текст", at: Date(timeIntervalSince1970: 5_000))
        let item = try! #require(model.items.first)
        await model.edit(item, text: "   ", at: Date())
        #expect(await repository.edits.isEmpty)
        await model.edit(item, text: " новый ", at: Date(timeIntervalSince1970: 6_000))
        #expect(model.items.first?.text == "новый")
        await model.sendNow(item)
        #expect(await repository.edits.map(\.text) == ["новый", "текст"])
        await model.cancel(item)
        #expect(model.items.isEmpty)
    }

    @Test("Ошибка сервера уходит в экран, поле не очищается")
    func failure() async {
        let repository = ScheduledMessages()
        await repository.set(failure: .networkUnavailable)
        let model = ScheduledMessagesModel(chatId: "c", repository: repository)
        var errors: [MaxlyError] = []
        var cleared = false
        model.onError = { errors.append($0) }
        model.onScheduled = { cleared = true }
        await model.schedule(text: "текст", at: Date())
        #expect(errors == [.networkUnavailable])
        #expect(!cleared)
    }

    @Test("Экран чата: отложенное из черновика очищает поле и показывает уведомление")
    func chatViewModelWiring() async {
        let repository = ScheduledMessages()
        let chat = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        chat.draft = "на потом"
        await chat.scheduled.schedule(text: chat.draft, at: Date(timeIntervalSince1970: 1_000))
        #expect(chat.draft.isEmpty)
        #expect(chat.notice == "Сообщение запланировано")
        #expect(chat.scheduled.items.map(\.text) == ["на потом"])
    }
}
