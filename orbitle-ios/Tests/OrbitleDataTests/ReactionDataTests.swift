import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

private func record(
    _ id: String,
    text: String = "Текст",
    status: MessageStatus = .sent,
    at seconds: TimeInterval = 1,
    reactions: [MessageReaction] = [],
    reactionsKnown: Bool = false,
    threadOf: String = ""
) -> MessageRecord {
    var content = MessageContent(reactions: reactions)
    if !threadOf.isEmpty { content.threadOf = threadOf }
    return MessageRecord(
        id: id,
        serverId: id,
        chatId: "c1",
        authorId: "bob",
        text: text,
        timestamp: Date(timeIntervalSince1970: seconds),
        status: status,
        contentJSON: MessageContentCodec.encode(content),
        threadOf: threadOf,
        reactionsKnown: reactionsKnown
    )
}

private func stored(_ repository: MessageRepositoryImpl, _ id: String) async throws -> [MessageReaction] {
    let rows = try await repository.page(chatId: "c1", before: nil, limit: 200)
    return try #require(rows.first { $0.id == id }).domain.content.reactions
}

private func counters(_ pairs: [(String, Int)], mine: String?, known: Bool = true) -> ReactionUpdate {
    ReactionUpdate(counters: pairs.map { ReactionUpdate.Counter(emoji: $0.0, count: $0.1) }, mine: mine, mineKnown: known)
}

@Suite("Реакции: разбор")
struct ReactionCodecTests {
    @Test("reactionsJSON ядра: своя известна, неизвестна или её нет")
    func parse() throws {
        let known = try #require(MessageContentCodec.reactionUpdate(
            #"{"counters":[{"reaction":"👍","count":2},{"reaction":"🔥","count":"1"}],"totalCount":3,"yourReaction":"👍"}"#
        ))
        #expect(known == counters([("👍", 2), ("🔥", 1)], mine: "👍"))
        let none = try #require(MessageContentCodec.reactionUpdate(#"{"counters":[],"totalCount":0,"yourReaction":null}"#))
        #expect(none == counters([], mine: nil))
        let push = try #require(MessageContentCodec.reactionUpdate(#"{"counters":[{"reaction":"❤️","count":4}],"totalCount":4}"#))
        #expect(push == counters([("❤️", 4)], mine: nil, known: false))
        #expect(MessageContentCodec.reactionUpdate("") == nil)
        #expect(MessageContentCodec.reactionUpdate("  ") == nil)
        #expect(MessageContentCodec.reactionUpdate("[1]") == nil)
        #expect(MessageContentCodec.reactionUpdate("{oops") == nil)
    }

    @Test("Сообщение ядра: reactionsJSON важнее reactionInfo во фрагменте")
    func coreMessage() {
        let fresh = CoreMapping.message(CoreMessage(
            id: "10", chatId: "c1", authorId: "bob", text: "т", timeMs: 1_000,
            contentJSON: #"{"reactionInfo":{"counters":[{"reaction":"😭","count":9}],"yourReaction":"😭"}}"#,
            reactionsJSON: #"{"counters":[{"reaction":"👍","count":1}],"totalCount":1,"yourReaction":"👍"}"#
        ))
        #expect(fresh.reactionsKnown)
        #expect(fresh.domain.content.reactions == [MessageReaction(emoji: "👍", count: 1, mine: true)])

        let cleared = CoreMapping.message(CoreMessage(
            id: "11", chatId: "c1", authorId: "bob", text: "т", timeMs: 1_000,
            reactionsJSON: #"{"counters":[],"totalCount":0,"yourReaction":null}"#
        ))
        #expect(cleared.reactionsKnown)
        #expect(cleared.contentJSON.isEmpty)

        let partial = CoreMapping.message(CoreMessage(
            id: "12", chatId: "c1", authorId: "bob", text: "т", timeMs: 1_000,
            contentJSON: #"{"reactionInfo":{"counters":[{"reaction":"😭","count":9}]}}"#
        ))
        #expect(!partial.reactionsKnown)
        #expect(partial.domain.content.reactions == [MessageReaction(emoji: "😭", count: 9, mine: false)])
    }

    @Test("Пуш сообщения несёт реакции, пуш реакций записью не становится")
    func events() {
        let message = MessageRecord(CoreEvent(
            kind: .message, chatId: "c1", messageId: "20", authorId: "bob", text: "т", title: "", chatType: "",
            timeMs: 1_000, unread: -1,
            reactionsJSON: #"{"counters":[{"reaction":"🔥","count":2}],"totalCount":2,"yourReaction":null}"#
        ))
        #expect(message?.reactionsKnown == true)
        #expect(message?.domain.content.reactions == [MessageReaction(emoji: "🔥", count: 2, mine: false)])
        let edited = MessageRecord(CoreEvent(
            kind: .edited, chatId: "c1", messageId: "20", authorId: "bob", text: "п", title: "", chatType: "",
            timeMs: 1_000, unread: -1
        ))
        #expect(edited?.reactionsKnown == false)
        let reactions = MessageRecord(CoreEvent(
            kind: .reactions, chatId: "c1", messageId: "20", authorId: "", text: "", title: "", chatType: "",
            timeMs: 0, unread: -1, reactionsJSON: #"{"counters":[]}"#
        ))
        #expect(reactions == nil)
    }
}

@Suite("Реакции: база")
struct ReactionStoreTests {
    @Test("Свежие реакции истории заменяют прежние, в том числе пустые")
    func knownReplaces() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        try await repository.upsert([record("101", reactions: [MessageReaction(emoji: "❤️", count: 2, mine: true)])])
        try await repository.upsert([record("101", reactions: [], reactionsKnown: true)])
        #expect(try await stored(repository, "101").isEmpty)

        try await repository.upsert([record("101", reactions: [MessageReaction(emoji: "👍", count: 1, mine: false)], reactionsKnown: true)])
        #expect(try await stored(repository, "101") == [MessageReaction(emoji: "👍", count: 1, mine: false)])
    }

    @Test("Правка и запись без реакций их не стирают")
    func editKeeps() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        let heart = [MessageReaction(emoji: "❤️", count: 2, mine: true)]
        try await repository.upsert([record("101", reactions: heart)])
        var edit = record("101", text: "правка")
        edit.contentJSON = MessageContentCodec.encode(MessageContent(edited: true))
        #expect(try await repository.applyEdit(edit))
        let row = try #require(try await repository.page(chatId: "c1", before: nil).first)
        #expect(row.text == "правка")
        #expect(row.domain.content.edited == true)
        #expect(row.domain.content.reactions == heart)
    }

    @Test("Пуш реакций: счётчики сервера, своя остаётся, пока есть её счётчик")
    func pushApplies() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        try await repository.upsert([record("101", reactions: [MessageReaction(emoji: "❤️", count: 1, mine: true)])])
        try await repository.applyReactions(chatId: "c1", messageId: "101", update: counters([("❤️", 3), ("👍", 1)], mine: nil, known: false))
        #expect(try await stored(repository, "101") == [
            MessageReaction(emoji: "❤️", count: 3, mine: true),
            MessageReaction(emoji: "👍", count: 1, mine: false),
        ])
        // Чужой чат и неизвестное сообщение пропускаются.
        try await repository.applyReactions(chatId: "c2", messageId: "101", update: .none)
        try await repository.applyReactions(chatId: "c1", messageId: "999", update: .none)
        #expect(try await stored(repository, "101").count == 2)
    }

    @Test("Пуш через SyncEngine доходит до ленты")
    func syncEngine() async throws {
        let api = FakeMaxAPI()
        let (messages, outbox) = try await makeMessageStack(api: api)
        let chats = ChatRepositoryImpl.make(stack: try SwiftDataStack(inMemory: true), api: api)
        let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
        try await messages.upsert([record("101")])
        await sync.consume(CoreEvent(
            kind: .reactions, chatId: "c1", messageId: "101", authorId: "", text: "", title: "", chatType: "",
            timeMs: 0, unread: -1, reactionsJSON: #"{"counters":[{"reaction":"🔥","count":5}],"totalCount":5}"#
        ))
        #expect(try await stored(messages, "101") == [MessageReaction(emoji: "🔥", count: 5, mine: false)])
    }
}

@Suite("Реакции: своё нажатие")
struct ReactionToggleTests {
    @Test("Видно сразу, уходит на сервер, ответ сервера становится итогом")
    func optimisticThenServer() async throws {
        let api = FakeMaxAPI()
        let gate = Gate()
        await api.setReactionGate(gate)
        await api.setReactionResults([.success(counters([("👍", 7)], mine: nil, known: false))])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([record("101", reactions: [MessageReaction(emoji: "👍", count: 5, mine: false)])])

        let task = Task { try await repository.toggleReaction(messageId: "101", emoji: "👍") }
        #expect(await eventually { await gate.arrivals == 1 })
        #expect(try await stored(repository, "101") == [MessageReaction(emoji: "👍", count: 6, mine: true)])
        // Пуш во время ожидания не перебивает нажатие.
        try await repository.applyReactions(chatId: "c1", messageId: "101", update: counters([("👍", 5)], mine: nil, known: false))
        #expect(try await stored(repository, "101") == [MessageReaction(emoji: "👍", count: 6, mine: true)])
        await gate.open()
        try await task.value

        #expect(await api.reactionCalls == [.init(messageId: "101", postId: "", emoji: "👍")])
        // Сервер не назвал свою: это только что поставленная.
        #expect(try await stored(repository, "101") == [MessageReaction(emoji: "👍", count: 7, mine: true)])
    }

    @Test("Снятие своей уходит без эмодзи")
    func remove() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([record("101", reactions: [MessageReaction(emoji: "❤️", count: 1, mine: true)])])
        try await repository.toggleReaction(messageId: "101", emoji: "❤️")
        #expect(await api.reactionCalls == [.init(messageId: "101", postId: "", emoji: nil)])
        #expect(try await stored(repository, "101").isEmpty)
    }

    @Test("Отказ сервера возвращает прежнее и пробрасывает ошибку")
    func rollback() async throws {
        let api = FakeMaxAPI()
        await api.setReactionResults([.failure(.offline)])
        let (repository, _) = try await makeMessageStack(api: api)
        let start = [MessageReaction(emoji: "❤️", count: 2, mine: true)]
        try await repository.upsert([record("101", reactions: start)])
        await #expect(throws: OrbitleError.networkUnavailable) {
            try await repository.toggleReaction(messageId: "101", emoji: "👍")
        }
        #expect(try await stored(repository, "101") == start)
    }

    @Test("Из быстрых нажатий итог даёт последнее, ответ на прежнее не применяется")
    func latestWins() async throws {
        let api = FakeMaxAPI()
        let gate = Gate()
        await api.setReactionGate(gate)
        await api.setReactionResults([
            .failure(.offline),
            .success(counters([("🔥", 1)], mine: "🔥")),
        ])
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([record("101")])

        let first = Task { try await repository.toggleReaction(messageId: "101", emoji: "👍") }
        #expect(await eventually { await gate.arrivals == 1 })
        let second = Task { try await repository.toggleReaction(messageId: "101", emoji: "🔥") }
        #expect(await eventually { await gate.arrivals == 2 })
        #expect(try await stored(repository, "101") == [MessageReaction(emoji: "🔥", count: 1, mine: true)])
        await gate.open()
        // Обогнанный запрос молчит, даже если сервер отказал.
        try await first.value
        try await second.value
        #expect(try await stored(repository, "101") == [MessageReaction(emoji: "🔥", count: 1, mine: true)])
        #expect(await api.reactionCalls.map(\.emoji) == ["👍", "🔥"])
    }

    @Test("Неотправленное сообщение реакцию не принимает")
    func unsent() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([
            MessageRecord(id: "local-1", chatId: "c1", authorId: "me", text: "ждёт", timestamp: Date(timeIntervalSince1970: 1), status: .sending),
        ])
        await #expect(throws: OrbitleError.rejected("Сообщение ещё не отправлено")) {
            try await repository.toggleReaction(messageId: "local-1", emoji: "👍")
        }
        await #expect(throws: OrbitleError.invalidRequest) {
            try await repository.toggleReaction(messageId: "nope", emoji: "👍")
        }
        #expect(await api.reactionCalls.isEmpty)
    }

    @Test("Реакция на комментарий в ленте уходит с id поста")
    func threadPost() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        try await repository.upsert([record("300", threadOf: "200")])
        try await repository.toggleReaction(messageId: "300", emoji: "👍")
        #expect(await api.reactionCalls == [.init(messageId: "300", postId: "200", emoji: "👍")])
    }
}

@Suite("Реакции: сверка и каталог")
struct ReactionRefreshTests {
    @Test("Сверка 180 берёт отправленные сообщения окна вне истории; о ком сервер молчит — реакции остаются")
    func refresh() async throws {
        let api = FakeMaxAPI()
        await api.setFetchedReactions(.success(["102": counters([("🔥", 2)], mine: "🔥")]))
        let (repository, _) = try await makeMessageStack(api: api)
        let heart = [MessageReaction(emoji: "❤️", count: 1, mine: false)]
        try await repository.upsert([
            record("101", at: 1, reactions: heart),
            record("102", at: 2),
            MessageRecord(id: "local-1", chatId: "c1", authorId: "me", text: "ждёт", timestamp: Date(timeIntervalSince1970: 3), status: .sending),
        ])
        await repository.refreshReactions(chatId: "c1")
        #expect(await api.reactionFetches == [["102", "101"]])
        #expect(try await stored(repository, "101") == heart)
        #expect(try await stored(repository, "102") == [MessageReaction(emoji: "🔥", count: 2, mine: true)])
    }

    @Test("Пустой ответ 180 и пустые записи в нём реакции не стирают")
    func refreshEmptyReply() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        let thumbs = [MessageReaction(emoji: "👍", count: 1, mine: false)]
        try await repository.upsert([record("101", at: 1, reactions: thumbs), record("102", at: 2, reactions: thumbs)])

        await api.setFetchedReactions(.success([:]))
        await repository.refreshReactions(chatId: "c1")
        #expect(try await stored(repository, "101") == thumbs)

        await api.setFetchedReactions(.success(["101": .none, "102": counters([], mine: nil, known: false)]))
        await repository.refreshReactions(chatId: "c1")
        #expect(try await stored(repository, "101") == thumbs)
        #expect(try await stored(repository, "102") == thumbs)
    }

    @Test("Сверка перечитывает последнюю страницу историей: её реакции — итог, 180 для неё не нужен")
    func refreshReadsHistory() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        // В кэше реакции устарели: на 201 их не было, на 202 висит снятая.
        try await repository.upsert([
            record("201", at: 1),
            record("202", at: 2, reactions: [MessageReaction(emoji: "😭", count: 3, mine: false)]),
        ])
        await api.setHistory([
            record("201", at: 1, reactions: [MessageReaction(emoji: "👍", count: 1, mine: false)], reactionsKnown: true),
            record("202", at: 2, reactionsKnown: true),
        ])
        await repository.refreshReactions(chatId: "c1")
        #expect(try await stored(repository, "201") == [MessageReaction(emoji: "👍", count: 1, mine: false)])
        #expect(try await stored(repository, "202").isEmpty)
        #expect(await api.reactionFetches.isEmpty)
    }

    @Test("Ошибка истории при сверке: 180 сверяет всё окно, ничего не стирая")
    func refreshHistoryFailure() async throws {
        let api = FakeMaxAPI()
        let (repository, _) = try await makeMessageStack(api: api)
        let thumbs = [MessageReaction(emoji: "👍", count: 1, mine: false)]
        try await repository.upsert([record("101", at: 1, reactions: thumbs), record("102", at: 2)])
        await api.setHistoryError(.offline)
        await api.setFetchedReactions(.success(["102": counters([("🔥", 1)], mine: nil)]))
        await repository.refreshReactions(chatId: "c1")
        #expect(await api.reactionFetches == [["102", "101"]])
        #expect(try await stored(repository, "101") == thumbs)
        #expect(try await stored(repository, "102") == [MessageReaction(emoji: "🔥", count: 1, mine: false)])
    }

    @Test("Ошибка сверки ничего не трогает")
    func refreshFailure() async throws {
        let api = FakeMaxAPI()
        await api.setFetchedReactions(.failure(.offline))
        let (repository, _) = try await makeMessageStack(api: api)
        let heart = [MessageReaction(emoji: "❤️", count: 1, mine: false)]
        try await repository.upsert([record("101", reactions: heart)])
        await repository.refreshReactions(chatId: "c1")
        #expect(try await stored(repository, "101") == heart)
    }

    @Test("Каталог без пустых и повторов")
    func catalog() async throws {
        let (repository, _) = try await makeMessageStack(api: FakeMaxAPI())
        #expect(await repository.reactionCatalog() == ["👍", "🔥"])
    }
}

@Suite("Реакции: клиент ядра")
struct ReactionClientTests {
    @Test("Снятие уходит пустой строкой, ответ разбирается")
    func setReaction() async throws {
        let core = FakeMaxCore()
        await core.setReactions(reply: #"{"counters":[{"reaction":"👍","count":3}],"totalCount":3,"yourReaction":"👍"}"#)
        let client = MaxAPIClient(core: core)
        let update = try await client.setReaction(chatId: "c1", messageId: "10", postId: "", emoji: "👍").get()
        #expect(update == counters([("👍", 3)], mine: "👍"))
        await core.setReactions(reply: "")
        #expect(try await client.setReaction(chatId: "c1", messageId: "10", postId: "5", emoji: nil).get() == nil)
        #expect(await core.reactionCalls == ["c1/10//👍", "c1/10/5/"])
        await core.setReactions(error: CoreFailure(kind: "NETWORK", key: nil))
        #expect(await client.setReaction(chatId: "c1", messageId: "10", postId: "", emoji: "👍") == .failure(.offline))
    }

    @Test("Реакции по id, список отреагировавших, каталог")
    func loads() async throws {
        let core = FakeMaxCore()
        let anna = ReactionUser(userId: "7", name: "Анна", avatarURL: nil, emoji: "🔥")
        await core.setReactions(byId: ["10": #"{"counters":[{"reaction":"🔥","count":1}],"totalCount":1,"yourReaction":null}"#, "11": ""], users: [anna])
        let client = MaxAPIClient(core: core)
        let reactions = try await client.fetchReactions(chatId: "c1", messageIds: ["10", "11"]).get()
        #expect(reactions == ["10": counters([("🔥", 1)], mine: nil)])
        #expect(try await client.reactionUsers(chatId: "c1", messageId: "10").get() == [anna])
        #expect(try await client.reactionCatalog().get() == ["👍", "🔥"])
    }

    @Test("Комментарии: реакция уходит с id поста, неотправленный отклоняется")
    func comments() async throws {
        let core = FakeMaxCore()
        await core.setReactions(reply: #"{"counters":[{"reaction":"👍","count":1}],"totalCount":1,"yourReaction":"👍"}"#)
        let repository = CoreCommentsRepository(core: core)
        let update = try await repository.setReaction(chatId: "c1", postId: "5", commentId: "70", emoji: "👍")
        #expect(update == counters([("👍", 1)], mine: "👍"))
        #expect(await core.reactionCalls == ["c1/70/5/👍"])
        await #expect(throws: OrbitleError.rejected("Комментарий ещё не отправлен")) {
            _ = try await repository.setReaction(chatId: "c1", postId: "5", commentId: "local-1", emoji: "👍")
        }
    }
}

/// Сообщения так, как их отдаёт мост ядра: `contentJSON` из `messageContentJson`
/// (сырой `reactionInfo` сервера внутри) и `reactionsJSON` из `reactionsJson`.
private enum DeviceHistory {
    static let groupMessage = CoreMessage(
        id: "116765779164748382", chatId: "-70001", authorId: "9000000000003", text: "Ок, завтра созвонимся",
        timeMs: 1_781_704_393_993,
        contentJSON: #"{"reactionInfo":{"counters":[{"count":1,"reaction":"👍"}],"totalCount":1}}"#,
        authorName: "Мария", reactionsJSON: #"{"counters":[{"reaction":"👍","count":1}],"totalCount":1,"yourReaction":null}"#
    )

    static let channelCounters: [(String, Int)] = [("👍", 27), ("🤔", 18), ("💀", 5), ("😍", 5), ("🤡", 5), ("😭", 4), ("🤣", 4), ("👎", 1)]

    static var channelPost: CoreMessage {
        let counters = channelCounters.map { #"{"reaction":"\#($0.0)","count":\#($0.1)}"# }.joined(separator: ",")
        return CoreMessage(
            id: "116765257400649050", chatId: "-69110159553957", authorId: "", text: "Российскому ИИ-рынку не хватает 84 млрд руб.",
            timeMs: 1_781_708_681_185,
            contentJSON: #"{"elements":[{"type":"STRONG","from":0,"length":10}],"reactionInfo":{"counters":[\#(counters)],"totalCount":69}}"#,
            reactionsJSON: #"{"counters":[\#(counters)],"totalCount":69,"yourReaction":null}"#
        )
    }
}

@Suite("Реакции: история как на устройстве")
struct ReactionDeviceHistoryTests {
    private func stack(core: FakeMaxCore) async throws -> MessageRepositoryImpl {
        let stack = try SwiftDataStack(inMemory: true)
        return MessageRepositoryImpl.make(stack: stack, api: MaxAPIClient(core: core))
    }

    private func reactions(_ repository: MessageRepositoryImpl, chatId: String, id: String) async throws -> [MessageReaction] {
        let rows = try await repository.page(chatId: chatId, before: nil, limit: 200)
        return try #require(rows.first { $0.id == id }).domain.content.reactions
    }

    @Test("Реакции чужих сообщений группы и поста канала доходят до ленты")
    func historyShowsReactions() async throws {
        let core = FakeMaxCore()
        let repository = try await stack(core: core)

        await core.setHistory([DeviceHistory.groupMessage])
        try await repository.fetchLatest(chatId: "-70001")
        #expect(try await reactions(repository, chatId: "-70001", id: "116765779164748382") == [MessageReaction(emoji: "👍", count: 1, mine: false)])

        await core.setHistory([DeviceHistory.channelPost])
        try await repository.fetchLatest(chatId: "-69110159553957")
        let post = try await reactions(repository, chatId: "-69110159553957", id: "116765257400649050")
        #expect(post.map(\.emoji) == DeviceHistory.channelCounters.map(\.0))
        #expect(post.map(\.count) == DeviceHistory.channelCounters.map(\.1))
        #expect(post.allSatisfy { !$0.mine })
    }

    @Test("Возврат из фона: пустой ответ 180 не стирает реакции истории")
    func resumeKeepsReactions() async throws {
        let core = FakeMaxCore()
        let repository = try await stack(core: core)
        await core.setHistory([DeviceHistory.channelPost])
        try await repository.fetchLatest(chatId: "-69110159553957")

        // История при возврате пришла пустой, по 180 сервер ничего не прислал.
        await core.setReactions(byId: [:])
        await core.setHistory([])
        await repository.refreshReactions(chatId: "-69110159553957")
        let post = try await reactions(repository, chatId: "-69110159553957", id: "116765257400649050")
        #expect(post.count == DeviceHistory.channelCounters.count)
        #expect(post.first == MessageReaction(emoji: "👍", count: 27, mine: false))
    }
}
