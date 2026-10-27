import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Отправка и правка на «сервере»: запоминает текст и разметку; `failure` — ответ на любой запрос.
private actor ComposerMessages: MessageRepository {
    private(set) var sent: [(text: String, replyTo: String?, spans: [TextSpan])] = []
    private(set) var edits: [(id: String, text: String)] = []
    var failure: MaxlyError?

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) -> Bool { false }
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func send(text: String, chatId: String, replyTo: String?, formatting: [TextSpan]) async throws(MaxlyError) {
        if let failure { throw failure }
        sent.append((text, replyTo, formatting))
    }

    func edit(messageId: String, chatId: String, text: String, formatting: [TextSpan]) async throws(MaxlyError) {
        if let failure { throw failure }
        edits.append((messageId, text))
    }

    func set(failure: MaxlyError?) { self.failure = failure }
}

private func message(_ id: String, author: String = "me", text: String = "текст") -> Message {
    Message(id: id, serverId: id, chatId: "c", authorId: author, text: text, timestamp: Date(), status: .sent)
}

@Suite("Поле ввода")
@MainActor
struct ComposerModelTests {
    private func composer(
        _ repository: ComposerMessages = ComposerMessages(),
        drafts: FakeDrafts? = nil,
        delay: Duration = .milliseconds(10)
    ) -> ComposerModel {
        ComposerModel(chatId: "c", currentUserId: "me", repository: repository, drafts: drafts, draftDelay: delay, chats: nil)
    }

    @Test("Черновик ложится после паузы в наборе и сразу при уходе с поля")
    func draftSaving() async {
        let drafts = FakeDrafts()
        let typed = composer(drafts: drafts)
        typed.draft = "после паузы"
        #expect(await eventually { await drafts.drafts["c"] == "после паузы" })

        let left = composer(drafts: drafts, delay: .seconds(60))
        left.draft = "сразу"
        left.flushDraft()
        #expect(await eventually { await drafts.drafts["c"] == "сразу" })
    }

    @Test("Цитата из черновика встаёт, когда её сообщение пришло в ленту")
    func draftReplyWaitsForFeed() async {
        let drafts = FakeDrafts(replies: ["c": "12"])
        let model = composer(drafts: drafts)
        var feed: [Message] = []
        model.findReply = { id in feed.first { $0.serverId == id } }
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.replyTarget == nil)
        feed = [message("12", author: "bob")]
        model.resolveDraftReply()
        #expect(model.replyTarget?.id == "12")
        model.stop()
    }

    @Test("Отправка: хуки ленты, цитата уходит с текстом; ошибка возвращает текст, разметку и цитату")
    func sendAndFailure() async {
        let repository = ComposerMessages()
        let model = composer(repository)
        var willSendText = 0
        var willSend = 0
        var errors: [MaxlyError] = []
        model.onWillSendText = { willSendText += 1 }
        model.onWillSend = { willSend += 1 }
        model.onError = { errors.append($0) }
        model.beginReply(to: message("7", author: "bob"))
        model.draft = "привет"
        await model.send()
        #expect(await repository.sent.map(\.text) == ["привет"])
        #expect(await repository.sent.map(\.replyTo) == ["7"])
        #expect(model.draft.isEmpty)
        #expect(model.replyTarget == nil)
        #expect(willSendText == 1 && willSend == 1)

        await repository.set(failure: .networkUnavailable)
        model.beginReply(to: message("8", author: "bob"))
        model.draft = "жирный"
        model.formatSelection = 0..<6
        model.toggleFormat(.strong)
        await model.send()
        #expect(errors == [.networkUnavailable])
        #expect(model.draft == "жирный")
        #expect(!model.format.spans.isEmpty)
        #expect(model.replyTarget?.id == "8")
    }

    @Test("Правка: отмена возвращает черновик, неушедшая правка возвращается в поле")
    func editing() async {
        let repository = ComposerMessages()
        let model = composer(repository)
        let own = message("5", text: "было")
        #expect(model.canEdit(own))
        #expect(!model.canEdit(message("6", author: "bob")))
        model.draft = "черновик"
        model.beginEdit(own)
        #expect(model.draft == "было")
        model.cancelEdit()
        #expect(model.draft == "черновик")
        #expect(model.editTarget == nil)

        await repository.set(failure: .networkUnavailable)
        model.beginEdit(own)
        model.draft = "стало"
        await model.send()
        #expect(model.editTarget?.id == "5")
        #expect(model.draft == "стало")

        await repository.set(failure: nil)
        await model.send()
        #expect(await repository.edits.map(\.text) == ["стало"])
        #expect(model.editTarget == nil)
        #expect(model.draft == "черновик")
    }

    @Test("Упоминание заменяет набранное после «@» и уходит отметкой с текстом")
    func mention() async {
        let repository = ComposerMessages()
        let model = composer(repository)
        model.draft = "Привет, @ан"
        model.insertMention(ChatMemberRef(id: "42", name: "Анна"))
        #expect(model.draft == "Привет, @Анна ")
        await model.send()
        #expect(await repository.sent.first?.spans.isEmpty == false)
    }

    @Test("Удаление цитируемого сообщения снимает ответ")
    func dropReply() {
        let model = composer()
        model.beginReply(to: message("9", author: "bob"))
        model.dropReply(ifIn: ["1", "2"])
        #expect(model.replyTarget?.id == "9")
        model.dropReply(ifIn: ["9"])
        #expect(model.replyTarget == nil)
    }
}
