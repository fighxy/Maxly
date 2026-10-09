import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Репозиторий сообщений, который запоминает реакции и отвечает заданной ошибкой.
private actor ReactionMessages: MessageRepository {
    private(set) var toggles: [String] = []
    private(set) var refreshed: [String] = []
    private(set) var catalogCalls = 0
    var toggleError: MaxlyError?
    var catalog: [String] = []
    var users: [ReactionUser] = []
    var usersError: MaxlyError?

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) {}
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func toggleReaction(messageId: String, emoji: String) async throws(MaxlyError) {
        toggles.append("\(messageId):\(emoji)")
        if let toggleError { throw toggleError }
    }

    func refreshReactions(chatId: String) async { refreshed.append(chatId) }

    func reactionUsers(messageId: String) async throws(MaxlyError) -> [ReactionUser] {
        if let usersError { throw usersError }
        return users
    }

    func reactionCatalog() async -> [String] {
        catalogCalls += 1
        return catalog
    }

    func set(toggleError: MaxlyError?) { self.toggleError = toggleError }
    func set(catalog: [String]) { self.catalog = catalog }
    func set(users: [ReactionUser], error: MaxlyError? = nil) {
        self.users = users
        self.usersError = error
    }
}

/// Комментарии, отвечающие на реакцию заданным результатом.
private actor ReactionComments: CommentsRepository {
    private let stored: [Message]
    private(set) var calls: [String?] = []
    var result: Result<ReactionUpdate?, MaxlyError> = .success(nil)

    init(_ stored: [Message]) { self.stored = stored }

    func comments(chatId: String, postId: String, before: Date?, limit: Int) async throws(MaxlyError) -> [Message] {
        before == nil ? stored : []
    }

    func send(text: String, chatId: String, postId: String) async throws(MaxlyError) -> Message {
        throw .invalidRequest
    }

    func setReaction(chatId: String, postId: String, commentId: String, emoji: String?) async throws(MaxlyError) -> ReactionUpdate? {
        calls.append(emoji)
        return try result.get()
    }

    func set(result: Result<ReactionUpdate?, MaxlyError>) { self.result = result }
}

private func message(_ id: String, serverId: String? = "100", status: MessageStatus = .sent, reactions: [MessageReaction] = []) -> Message {
    Message(
        id: id, serverId: serverId, chatId: "c", authorId: "anna", text: "Текст",
        timestamp: Date(timeIntervalSince1970: 1), status: status,
        content: MessageContent(reactions: reactions)
    )
}

@Suite("Реакции: палитра")
struct ReactionPaletteTests {
    @Test("Быстрый ряд: каталог или запасной набор, своя реакция всегда в нём")
    func quickRow() {
        #expect(ReactionPalette.quick(catalog: []) == ReactionPalette.fallback)
        let catalog = ["😀", "😁", "😂", "🤣", "😃", "😄", "😅", "😆"]
        #expect(ReactionPalette.quick(catalog: catalog) == Array(catalog.prefix(6)))
        #expect(ReactionPalette.quick(catalog: catalog, mine: "😂") == Array(catalog.prefix(6)))
        #expect(ReactionPalette.quick(catalog: catalog, mine: "🦄") == ["🦄", "😀", "😁", "😂", "🤣", "😃"])
        #expect(ReactionPalette.quick(catalog: ["👍"], mine: "🦄") == ["🦄", "👍"])
    }

    @Test("Число на плашке")
    func countText() {
        #expect(ReactionPalette.countText(0) == "0")
        #expect(ReactionPalette.countText(7) == "7")
        #expect(ReactionPalette.countText(999) == "999")
        #expect(ReactionPalette.countText(1000) == "1K")
        #expect(ReactionPalette.countText(1250) == "1,2K")
        #expect(ReactionPalette.countText(1999) == "1,9K")
        #expect(ReactionPalette.countText(15_400) == "15K")
        #expect(ReactionPalette.countText(3_450_000) == "3,4M")
        #expect(ReactionPalette.countText(-3) == "0")
    }
}

@Suite("Реакции: экран чата")
@MainActor
struct ChatReactionTests {
    @Test("Нажатие уходит в репозиторий, ошибка показывается и уходит после удачи")
    func toggleAndFailure() async {
        let repository = ReactionMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.toggleReaction(messageId: "m1", emoji: "👍")
        #expect(await repository.toggles == ["m1:👍"])
        #expect(model.errorMessage == nil)

        await repository.set(toggleError: .networkUnavailable)
        await model.toggleReaction(messageId: "m1", emoji: "🔥")
        #expect(model.errorMessage == "Не удалось обновить реакцию")

        await repository.set(toggleError: nil)
        await model.toggleReaction(messageId: "m1", emoji: "🔥")
        #expect(model.errorMessage == nil)
    }

    @Test("Отказ с пояснением показывает само пояснение, отмена молчит")
    func rejectedAndCancelled() async {
        let repository = ReactionMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await repository.set(toggleError: .cancelled)
        await model.toggleReaction(messageId: "m1", emoji: "👍")
        #expect(model.errorMessage == nil)
        await repository.set(toggleError: .rejected("Сообщение ещё не отправлено"))
        await model.toggleReaction(messageId: "m1", emoji: "👍")
        #expect(model.errorMessage == "Сообщение ещё не отправлено")
    }

    @Test("Каталог грузится один раз при открытии и задаёт быстрый ряд")
    func catalog() async {
        let repository = ReactionMessages()
        await repository.set(catalog: ["😀", "😁", "😂", "🤣", "😃", "😄", "😅"])
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        #expect(model.quickReactions(for: message("m1")) == ReactionPalette.fallback)
        model.activate()
        for _ in 0..<200 where model.reactionCatalog.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.reactionCatalog.count == 7)
        #expect(model.quickReactions(for: message("m1")) == ["😀", "😁", "😂", "🤣", "😃", "😄"])
        let mine = message("m2", reactions: [MessageReaction(emoji: "🦄", count: 1, mine: true)])
        #expect(model.quickReactions(for: mine).first == "🦄")
        model.deactivate()
        model.activate()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await repository.catalogCalls == 1)
        model.deactivate()
    }

    @Test("Реакции только у принятых сервером сообщений")
    func canReact() {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: ReactionMessages())
        #expect(model.canReact(message("m1")))
        #expect(!model.canReact(message("local-1", serverId: nil, status: .sending)))
        #expect(!model.canReact(message("m2", status: .failed)))
        #expect(!model.canReact(message("m3", serverId: "local-3")))
    }

    @Test("Полный выбор ставит реакцию на своё сообщение и закрывается")
    func picker() async {
        let repository = ReactionMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.showMoreReactions(message("local-1", serverId: nil, status: .sending))
        #expect(model.reactionPickerTarget == nil)
        model.showMoreReactions(message("m1"))
        #expect(model.reactionPickerTarget?.id == "m1")
        await model.pickReaction("🦄")
        #expect(model.reactionPickerTarget == nil)
        #expect(await repository.toggles == ["m1:🦄"])
    }

    @Test("Сверка реакций уходит в репозиторий по чату")
    func refresh() async {
        let repository = ReactionMessages()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        await model.refreshReactions()
        #expect(await repository.refreshed == ["c"])
    }

    @Test("Кто отреагировал: список, отбор и ошибка")
    func users() async {
        let repository = ReactionMessages()
        await repository.set(users: [
            ReactionUser(userId: "1", name: "Анна", avatarURL: nil, emoji: "👍"),
            ReactionUser(userId: "2", name: " ", avatarURL: nil, emoji: "🔥"),
        ])
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.showReactionUsers(message("m0"))
        #expect(model.reactionUsers == nil)
        let reacted = message("m1", reactions: [
            MessageReaction(emoji: "👍", count: 1, mine: false),
            MessageReaction(emoji: "🔥", count: 1, mine: false),
        ])
        model.showReactionUsers(reacted)
        let list = try? #require(model.reactionUsers)
        guard let list else { return }
        #expect(list.title == "Реакции: 2")
        #expect(list.state == .loading)
        await list.load()
        #expect(list.state == .loaded)
        #expect(list.visible.map(\.userId) == ["1", "2"])
        list.filter = "🔥"
        #expect(list.visible.map(\.userId) == ["2"])
        #expect(ReactionUsersViewModel.name(of: list.visible[0]) == "Пользователь 2")
        list.filter = "🦄"
        #expect(list.emptyText == "Никто не отреагировал")

        await repository.set(users: [], error: .networkUnavailable)
        await list.load()
        #expect(list.state == .failed("Не удалось загрузить список"))
    }
}

@Suite("Реакции: комментарии")
@MainActor
struct CommentReactionTests {
    private let post = Message(id: "p1", serverId: "500", chatId: "c", authorId: "channel", text: "Пост", timestamp: Date(timeIntervalSince1970: 1), status: .sent)

    private func comment(_ reactions: [MessageReaction] = []) -> Message {
        Message(
            id: "700", serverId: "700", chatId: "c", authorId: "anna", text: "Комментарий",
            timestamp: Date(timeIntervalSince1970: 2), status: .sent, content: MessageContent(reactions: reactions)
        )
    }

    @Test("Своя реакция видна сразу, ответ сервера становится итогом")
    func optimisticThenServer() async {
        let repository = ReactionComments([comment([MessageReaction(emoji: "👍", count: 2, mine: false)])])
        await repository.set(result: .success(ReactionUpdate(
            counters: [.init(emoji: "👍", count: 5)], mine: nil, mineKnown: false
        )))
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository)
        await model.load()
        await model.toggleReaction(commentId: "700", emoji: "👍")
        #expect(await repository.calls == ["👍"])
        // Сервер не назвал свою: это та, что только что поставлена.
        #expect(model.comments[0].content.reactions == [MessageReaction(emoji: "👍", count: 5, mine: true)])
        #expect(model.errorMessage == nil)
    }

    @Test("Отказ сервера возвращает прежние реакции")
    func rollback() async {
        let start = [MessageReaction(emoji: "❤️", count: 1, mine: true)]
        let repository = ReactionComments([comment(start)])
        await repository.set(result: .failure(.networkUnavailable))
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository)
        await model.load()
        await model.toggleReaction(commentId: "700", emoji: "❤️")
        #expect(await repository.calls == [nil])
        #expect(model.comments[0].content.reactions == start)
        #expect(model.errorMessage == "Не удалось обновить реакцию")
    }

    @Test("Ответ без реакций оставляет оптимистичное состояние")
    func silentServer() async {
        let repository = ReactionComments([comment()])
        let model = CommentsViewModel(chatId: "c", post: post, currentUserId: "me", comments: repository, reactionCatalog: ["🦄"])
        await model.load()
        #expect(model.quickReactions(for: model.comments[0]) == ["🦄"])
        await model.toggleReaction(commentId: "700", emoji: "🦄")
        #expect(model.comments[0].content.reactions == [MessageReaction(emoji: "🦄", count: 1, mine: true)])
    }
}
