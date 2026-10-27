import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Удаление и пересылка на «сервере»; `failure` — ответ на любой запрос.
private actor ActionMessages: MessageRepository {
    private(set) var deleted: [(ids: [String], forEveryone: Bool)] = []
    private(set) var forwarded: [(id: String, to: String)] = []
    var failure: MaxlyError?

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) -> Bool { false }
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func deletePlan(messageIds: [String], chatId: String) async -> MessageSelectionRules.DeleteOptions? {
        MessageSelectionRules.DeleteOptions(canDelete: true, showsForEveryone: true, forcesForEveryone: false, forEveryoneByDefault: true)
    }

    func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(MaxlyError) {
        if let failure { throw failure }
        deleted.append((messageIds, forEveryone))
    }

    func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(MaxlyError) {
        if let failure { throw failure }
        forwarded.append((messageId, targetChatId))
    }

    func set(failure: MaxlyError?) { self.failure = failure }
}

private func sent(_ id: String) -> Message {
    Message(id: id, serverId: id, chatId: "c", authorId: "me", text: "текст", timestamp: Date(), status: .sent)
}

@Suite("Меню сообщения: удаление и пересылка")
@MainActor
struct MessageActionsModelTests {
    @Test("«Удалить»: варианты от ядра, подтверждение снимает цитату и уходит на сервер")
    func delete() async {
        let repository = ActionMessages()
        let selection = MessageSelectionModel(chatId: "c", currentUserId: "me", repository: repository)
        let model = MessageActionsModel(chatId: "c", repository: repository, selection: selection)
        var willDelete: [String] = []
        model.onWillDelete = { willDelete.append($0) }
        model.requestDelete(sent("100"))
        #expect(await eventually { model.deletionCandidate?.id == "100" })
        #expect(model.deletionShowsEveryone)
        #expect(model.deletionPrefersEveryone)
        #expect(!model.deletionForcesEveryone)
        await model.confirmDelete(forEveryone: true)
        #expect(model.deletionCandidate == nil)
        #expect(willDelete == ["100"])
        #expect(await repository.deleted.map(\.ids) == [["100"]])
        #expect(await repository.deleted.map(\.forEveryone) == [true])
    }

    @Test("Пересылка: уведомление, ошибка уходит в экран")
    func forward() async {
        let repository = ActionMessages()
        let selection = MessageSelectionModel(chatId: "c", currentUserId: "me", repository: repository)
        let model = MessageActionsModel(chatId: "c", repository: repository, selection: selection)
        var notices: [String] = []
        var errors: [MaxlyError] = []
        model.onNotice = { notices.append($0) }
        model.onError = { errors.append($0) }
        model.requestForward(sent("7"))
        await model.forward(to: "other")
        #expect(model.forwardCandidate == nil)
        #expect(await repository.forwarded.map(\.to) == ["other"])
        #expect(notices == ["Сообщение переслано"])
        await repository.set(failure: .networkUnavailable)
        model.requestForward(sent("8"))
        await model.forward(to: "other")
        #expect(errors == [.networkUnavailable])
    }

    @Test("Экран чата: удаление сообщения из цитаты снимает ответ")
    func chatViewModelWiring() async {
        let repository = ActionMessages()
        let chat = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        let target = sent("5")
        chat.composer.beginReply(to: target)
        #expect(chat.composer.replyTarget?.id == "5")
        await chat.actions.confirmDelete(target, forEveryone: false)
        #expect(chat.composer.replyTarget == nil)
    }
}
