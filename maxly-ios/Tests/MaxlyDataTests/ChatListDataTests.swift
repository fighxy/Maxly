import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

/// Часы, которые двигает тест. Нужны для черновиков и срока «печатает…».
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private struct ListParts {
    let api: FakeMaxAPI
    let chats: ChatRepositoryImpl
    let messages: MessageRepositoryImpl
    let sync: SyncEngine
    let clock: ManualClock
}

private func makeParts(user: String = "me") async throws -> ListParts {
    let api = FakeMaxAPI()
    let stack = try SwiftDataStack(inMemory: true)
    let clock = ManualClock()
    let chats = ChatRepositoryImpl(modelContainer: stack.container, api: api, typingTTL: 5, clock: { clock.now })
    let messages = MessageRepositoryImpl.make(stack: stack, api: api)
    let outbox = OutboxQueue(api: api, sleep: { _ in })
    await messages.attach(outbox: outbox)
    let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
    await sync.connectOutgoing()
    await messages.setCurrentUser(id: user)
    return ListParts(api: api, chats: chats, messages: messages, sync: sync, clock: clock)
}

private func coreEvent(_ kind: CoreEvent.Kind, chat: String = "c1", message: String = "", author: String = "", text: String = "", at seconds: Int64 = 0, authorName: String = "") -> CoreEvent {
    CoreEvent(kind: kind, chatId: chat, messageId: message, authorId: author, text: text, title: "", chatType: "", timeMs: seconds * 1000, unread: -1, authorName: authorName)
}

/// Кто печатает: id чата → id пользователей по порядку.
private func typingIds(_ chats: ChatRepositoryImpl) async -> [String: [String]] {
    (await first(chats.typing()) ?? [:]).mapValues { $0.map(\.userId) }
}

private func first<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
    for await value in stream { return value }
    return nil
}

private func chatRow(_ chats: ChatRepositoryImpl, _ id: String = "c1") async -> Chat? {
    await first(chats.chats())?.first { $0.id == id }
}

@Suite("Список чатов: данные строки")
struct ChatListDataTests {
    @Test("Закрепление уходит на сервер целиком: новый первым, порядок, открепление")
    func pins() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a"), makeChat(id: "b"), makeChat(id: "c")])
        #expect(parts.chats.capabilities.contains(.pin))
        #expect(parts.chats.capabilities.contains(.mute))

        try await parts.chats.setPinned(true, chatId: "b")
        try await parts.chats.setPinned(true, chatId: "c")
        #expect(await parts.api.pinCalls == [["b"], ["c", "b"]])
        var rows = try #require(await first(parts.chats.chats()))
        #expect(rows.filter(\.isPinned).sorted(by: Chat.listOrder).map(\.id) == ["c", "b"])

        try await parts.chats.reorderPinned(["b", "c"])
        #expect(await parts.api.pinCalls.last == ["b", "c"])
        // Ответ списка чатов без сведений о закреплённых их не сбрасывает.
        try await parts.chats.upsert([makeChat(id: "b"), makeChat(id: "c")])
        rows = try #require(await first(parts.chats.chats()))
        #expect(rows.filter(\.isPinned).sorted(by: Chat.listOrder).map(\.id) == ["b", "c"])

        try await parts.chats.setPinned(false, chatId: "b")
        #expect(await parts.api.pinCalls.last == ["c"])
        #expect(await chatRow(parts.chats, "b")?.isPinned == false)
        #expect(await chatRow(parts.chats, "c")?.isPinned == true)

        // Повтор уже сделанного на сервер не уходит.
        try await parts.chats.setPinned(true, chatId: "c")
        try await parts.chats.setPinned(false, chatId: "a")
        try await parts.chats.reorderPinned(["c"])
        #expect(await parts.api.pinCalls.count == 4)
        // Неизвестный чат закрепить нельзя.
        await #expect(throws: MaxlyError.invalidRequest) { try await parts.chats.setPinned(true, chatId: "missing") }
    }

    @Test("Удалили своё последнее фото: строка показывает предыдущее сообщение без миниатюры")
    func deleteLastUpdatesRow() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([ChatRecord(
            id: "c1", title: "Избранное", type: .private, lastMessageId: "102",
            updatedAt: Date(timeIntervalSince1970: 2), preview: "",
            lastMedia: .photo, lastThumbnailURL: URL(string: "https://example.invalid/p.jpg")
        )])
        try await parts.messages.upsert([
            MessageRecord(id: "101", chatId: "c1", authorId: "me", text: "Раньше", timestamp: Date(timeIntervalSince1970: 1), status: .sent),
            MessageRecord(id: "102", chatId: "c1", authorId: "me", text: "", timestamp: Date(timeIntervalSince1970: 2), status: .sent),
        ])
        try await parts.messages.delete(messageIds: ["102"], chatId: "c1", forEveryone: true)
        let row = try #require(await chatRow(parts.chats))
        #expect(row.preview == "Раньше")
        #expect(row.lastMessage?.media == nil)
        #expect(row.lastMessage?.thumbnailURL == nil)
    }

    @Test("Новое последнее сообщение — фото без подписи: текст прежнего не остаётся, строка пишет вид вложения")
    func newPhotoReplacesOldText() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([ChatRecord(
            id: "c1", title: "Ленина 33", type: .group, lastMessageId: "201",
            updatedAt: Date(timeIntervalSince1970: 10), preview: "Встречаемся в семь", lastAuthorId: "u1"
        )])
        // Так строку присылает ядро: у фото текста нет, вид вложения — `photo`.
        try await parts.chats.upsert([ChatRecord(
            id: "c1", title: "Ленина 33", type: .group, lastMessageId: "202",
            updatedAt: Date(timeIntervalSince1970: 20), preview: nil, lastAuthorId: "u2",
            lastMedia: .photo, lastThumbnailURL: URL(string: "https://example.invalid/p.jpg"),
            lastAuthorName: "Ольга"
        )])
        let row = try #require(await chatRow(parts.chats))
        #expect(row.preview == nil)
        #expect(row.lastMessage?.media == .photo)
        #expect(row.lastMessage?.authorName == "Ольга")
        // То же сообщение ещё раз без текста (повтор списка) уже ничего не стирает.
        try await parts.chats.upsert([ChatRecord(
            id: "c1", title: "Ленина 33", type: .group, lastMessageId: "202",
            updatedAt: Date(timeIntervalSince1970: 20), preview: "подпись"
        )])
        try await parts.chats.upsert([ChatRecord(
            id: "c1", title: "Ленина 33", type: .group, lastMessageId: "202",
            updatedAt: Date(timeIntervalSince1970: 20), preview: nil
        )])
        #expect(await chatRow(parts.chats)?.preview == "подпись")
    }

    @Test("Сервер прислал строку без сообщений: превью удалённой фотографии пропадает")
    func emptyChatClearsRow() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([ChatRecord(
            id: "0", title: "", type: .private, lastMessageId: "102",
            updatedAt: Date(timeIntervalSince1970: 50), preview: "",
            lastMedia: .photo, lastThumbnailURL: URL(string: "https://example.invalid/p.jpg")
        )])
        try await parts.chats.upsert([ChatRecord(id: "0", title: "", type: .private, updatedAt: Date(timeIntervalSince1970: 0), lastKnown: true)])
        let row = try #require(await chatRow(parts.chats, "0"))
        #expect(row.lastMessageId == nil)
        #expect(row.lastMessage?.media == nil)
        #expect(row.lastMessage?.thumbnailURL == nil)
    }

    @Test("Звук чата: база меняется сразу, запрос на сервер, ошибка возвращает строку как была")
    func mute() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a")])
        try await parts.chats.setMuted(true, chatId: "a")
        #expect(await parts.api.muteCalls.map { $0.0 } == ["a"])
        #expect(await parts.api.muteCalls.map { $0.1 } == [true])
        #expect(await chatRow(parts.chats, "a")?.isMuted == true)

        await parts.api.setMuteError(.offline)
        await #expect(throws: MaxlyError.self) { try await parts.chats.setMuted(false, chatId: "a") }
        #expect(await chatRow(parts.chats, "a")?.isMuted == true)
        await #expect(throws: MaxlyError.invalidRequest) { try await parts.chats.setMuted(true, chatId: "missing") }
    }

    @Test("Звук чата: строка меняется до ответа сервера, отказ сервера её откатывает")
    func muteIsOptimistic() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a")])
        await parts.api.setMuteError(.offline)
        var updates = parts.chats.chats().makeAsyncIterator()
        let before = await updates.next()
        #expect(before?.first { $0.id == "a" }?.isMuted == false)
        await #expect(throws: MaxlyError.self) { try await parts.chats.setMuted(true, chatId: "a") }
        let optimistic = await updates.next()
        let rolledBack = await updates.next()
        #expect(optimistic?.first { $0.id == "a" }?.isMuted == true)
        #expect(rolledBack?.first { $0.id == "a" }?.isMuted == false)
    }

    @Test("Звук чата: список, запрошенный до переключения, метку не сбрасывает, следующий применяется")
    func muteSurvivesStaleList() async throws {
        let parts = try await makeParts()
        var stale = makeChat(id: "a")
        stale.isMuted = false
        try await parts.chats.upsert([stale])
        await parts.api.setChats([stale])
        let gate = Gate()
        await parts.api.setFetchGate(gate)

        // Опрос ушёл до нажатия: ядро считает звук по старому конфигу.
        let refresh = Task { try await parts.chats.refresh() }
        #expect(await eventually { await gate.arrivals == 1 })
        try await parts.chats.setMuted(true, chatId: "a")
        await gate.open()
        try await refresh.value
        #expect(await chatRow(parts.chats, "a")?.isMuted == true)

        // Список, запрошенный после ответа сервера, снова главный: звук включили на другом устройстве.
        try await parts.chats.refresh()
        #expect(await chatRow(parts.chats, "a")?.isMuted == false)
    }

    @Test("Закреплённые с сервера: порядок сервера, остальные откреплены, догруженные чаты встают на место")
    func serverPins() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a"), makeChat(id: "b"), makeChat(id: "c")])
        try await parts.chats.setPinned(true, chatId: "a")

        // С другого устройства: закреплены c, потом d (его ещё нет в базе), потом b.
        try await parts.chats.applyServerPins(["c", "d", "b", "c", ""])
        var rows = try #require(await first(parts.chats.chats()))
        #expect(rows.filter(\.isPinned).sorted(by: Chat.listOrder).map(\.id) == ["c", "b"])
        #expect(rows.first { $0.id == "a" }?.isPinned == false)

        // d приходит следующей страницей и сразу встаёт между c и b.
        try await parts.chats.upsert([makeChat(id: "d"), makeChat(id: "e")])
        rows = try #require(await first(parts.chats.chats()))
        #expect(rows.filter(\.isPinned).sorted(by: Chat.listOrder).map(\.id) == ["c", "d", "b"])
        #expect(rows.first { $0.id == "e" }?.isPinned == false)

        // Следующее действие строится от списка сервера, а не только от строк базы.
        try await parts.chats.setPinned(true, chatId: "e")
        #expect(await parts.api.pinCalls.last == ["e", "c", "d", "b"])
        // Перестановка видимых сохраняет остальных закреплённых после них.
        try await parts.chats.reorderPinned(["b", "e"])
        #expect(await parts.api.pinCalls.last == ["b", "e", "c", "d"])

        // Всё открепили на другом устройстве.
        try await parts.chats.applyServerPins([])
        rows = try #require(await first(parts.chats.chats()))
        #expect(rows.allSatisfy { !$0.isPinned })
    }

    @Test("Ошибка сервера: закреплённые в базе не меняются, ошибка доходит до экрана")
    func pinFailure() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a"), makeChat(id: "b")])
        try await parts.chats.applyServerPins(["a"])
        await parts.api.setPinError(.offline)

        await #expect(throws: MaxlyError.networkUnavailable) { try await parts.chats.setPinned(true, chatId: "b") }
        await #expect(throws: MaxlyError.networkUnavailable) { try await parts.chats.setPinned(false, chatId: "a") }
        let rows = try #require(await first(parts.chats.chats()))
        #expect(rows.filter(\.isPinned).map(\.id) == ["a"])

        // После ошибки следующее действие снова строится от подтверждённого списка.
        await parts.api.setPinError(nil)
        try await parts.chats.setPinned(true, chatId: "b")
        #expect(await parts.api.pinCalls.last == ["b", "a"])
    }

    @Test("Два быстрых закрепления: второе строится от первого, ещё не подтверждённого")
    func pinsInFlight() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a"), makeChat(id: "b")])
        try await parts.chats.applyServerPins([])
        let gate = Gate()
        await parts.api.setPinGate(gate)
        let chats = parts.chats
        let pinA = Task { try await chats.setPinned(true, chatId: "a") }
        #expect(await eventually { await gate.arrivals == 1 })
        let pinB = Task { try await chats.setPinned(true, chatId: "b") }
        #expect(await eventually { await gate.arrivals == 2 })
        await gate.open()
        try await pinA.value
        try await pinB.value
        #expect(await parts.api.pinCalls == [["a"], ["b", "a"]])
        let rows = try #require(await first(parts.chats.chats()))
        #expect(rows.filter(\.isPinned).sorted(by: Chat.listOrder).map(\.id) == ["b", "a"])
    }

    @Test("Поток закреплённых ядра пишется в базу, пока включены пуши")
    func pinsFromCore() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat(id: "a"), makeChat(id: "b")])
        let core = FakeMaxCore()
        // Вход уже прислал список до подписки: подписчик получает его сразу.
        core.pins.publish(["b"])
        await parts.sync.startEvents(core)
        #expect(await eventually { await chatRow(parts.chats, "b")?.isPinned == true })

        // Изменение с другого устройства.
        core.pins.publish(["a", "b"])
        #expect(await eventually {
            let rows = await first(parts.chats.chats()) ?? []
            return rows.filter(\.isPinned).sorted(by: Chat.listOrder).map(\.id) == ["a", "b"]
        })

        // После выхода список больше не пишется, подписка закрыта.
        await parts.sync.stopEvents()
        #expect(await eventually { core.pins.subscriberCount == 0 })
        core.pins.publish([])
        try await Task.sleep(for: .milliseconds(50))
        #expect(await chatRow(parts.chats, "a")?.isPinned == true)

        // Новый вход подписывается заново и сразу получает текущий список.
        await parts.sync.startEvents(core)
        #expect(await eventually { await chatRow(parts.chats, "a")?.isPinned == false })
        #expect(core.pins.subscriberCount == 1)
        await parts.sync.stopEvents()
    }

    @Test("Клиент ядра передаёт закреплённые и ошибку ядра")
    func pinsThroughClient() async throws {
        let core = FakeMaxCore()
        let client = MaxAPIClient(core: core)
        #expect(await client.setPinnedChats(["x", "y"]) == .success(["x", "y"]))
        #expect(await core.pinRequests == [["x", "y"]])
        await core.setPinError(CoreFailure(kind: "NETWORK", key: nil))
        #expect(await client.setPinnedChats(["y"]) == .failure(.offline))
    }

    @Test("Ручная пометка «непрочитано» хранится и снимается")
    func markedUnread() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        try await parts.chats.setMarkedUnread(true, chatId: "c1")
        #expect(await chatRow(parts.chats)?.isMarkedUnread == true)
        try await parts.chats.upsert([makeChat()])
        #expect(await chatRow(parts.chats)?.isMarkedUnread == true)
        try await parts.chats.setMarkedUnread(false, chatId: "c1")
        #expect(await chatRow(parts.chats)?.isMarkedUnread == false)
    }

    @Test("Черновик сохраняется с временем, пустой удаляет")
    func drafts() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        await parts.chats.saveDraft("  Привет  ", chatId: "c1")
        #expect(await parts.chats.draft(chatId: "c1") == "Привет")
        let draft = try #require(await chatRow(parts.chats)?.draft)
        #expect(draft == ChatDraft(text: "Привет", updatedAt: Date(timeIntervalSince1970: 1_000)))
        await parts.chats.saveDraft("", chatId: "c1")
        #expect(await parts.chats.draft(chatId: "c1") == nil)
        #expect(await chatRow(parts.chats)?.draft == nil)
        // Чата нет — черновик некуда положить.
        await parts.chats.saveDraft("текст", chatId: "missing")
        #expect(await parts.chats.draft(chatId: "missing") == nil)
    }

    @Test("Своё сообщение: «отправляется», «доставлено», «прочитано» по отметке собеседника")
    func delivery() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        let gate = Gate()
        await parts.api.setSendGate(gate)
        let messages = parts.messages
        // Отправка ждёт ответа сервера, поэтому идёт отдельной задачей.
        let sending = Task { try await messages.send(text: "Как дела?", chatId: "c1") }
        #expect(await eventually { await chatRow(parts.chats)?.lastMessage?.delivery == .sending })
        var last = try #require(await chatRow(parts.chats)?.lastMessage)
        #expect(last.isOutgoing)
        await gate.open()
        try await sending.value
        #expect(await eventually { await chatRow(parts.chats)?.lastMessage?.delivery == .sent })

        let sentAt = try #require(await chatRow(parts.chats)?.updatedAt)
        await parts.sync.consume(coreEvent(.read, author: "bob", at: Int64(sentAt.timeIntervalSince1970) + 1))
        last = try #require(await chatRow(parts.chats)?.lastMessage)
        #expect(last.delivery == .read)

        // Ответ собеседника: строка теперь про его сообщение.
        await parts.sync.consume(coreEvent(.message, message: "m200", author: "bob", text: "Норм", at: Int64(sentAt.timeIntervalSince1970) + 10))
        last = try #require(await chatRow(parts.chats)?.lastMessage)
        #expect(!last.isOutgoing)
        #expect(last.authorId == "bob")
        #expect(last.delivery == nil)
    }

    @Test("Не ушедшее сообщение помечает строку ошибкой")
    func failedSend() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        await parts.api.setSendResults([.failure(.rejected("нельзя"))])
        try await parts.messages.send(text: "Привет", chatId: "c1")
        #expect(await eventually { await chatRow(parts.chats)?.lastMessage?.delivery == .failed })
    }

    @Test("Своё сообщение с другого устройства видно как своё")
    func ownEcho() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        await parts.sync.consume(coreEvent(.message, message: "m300", author: "me", text: "С ноутбука", at: 500))
        let chat = try #require(await chatRow(parts.chats))
        #expect(chat.lastMessage?.isOutgoing == true)
        #expect(chat.lastMessage?.delivery == .sent)
        #expect(chat.unreadCount == 3)
    }

    @Test("Смена последнего сообщения с сервера сбрасывает автора")
    func serverResetsAuthor() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        await parts.sync.consume(coreEvent(.message, message: "m300", author: "me", text: "Моё", at: 500))
        try await parts.chats.upsert([ChatRecord(id: "c1", title: "", type: .group, lastMessageId: "m301", updatedAt: Date(timeIntervalSince1970: 600), preview: "Чужое")])
        let chat = try #require(await chatRow(parts.chats))
        #expect(chat.lastMessage == nil)
        #expect(chat.preview == "Чужое")
    }

    @Test("«Печатает…» живёт до срока, сообщение автора его снимает, свои пуши не считаются")
    func typing() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        await parts.sync.consume(coreEvent(.typing, author: "bob"))
        await parts.sync.consume(coreEvent(.typing, author: "me"))
        #expect(await typingIds(parts.chats) == ["c1": ["bob"]])

        parts.clock.advance(3)
        await parts.sync.consume(coreEvent(.typing, author: "ann"))
        parts.clock.advance(3)
        await parts.chats.expireTyping()
        #expect(await typingIds(parts.chats) == ["c1": ["ann"]])

        await parts.sync.consume(coreEvent(.message, message: "m500", author: "ann", text: "Готово", at: 900))
        #expect(await typingIds(parts.chats) == [:])
    }

    @Test("Печатающие идут по началу, с типом из пуша и именем из сохранённых сообщений")
    func typingDetails() async throws {
        let parts = try await makeParts()
        try await parts.chats.upsert([makeChat()])
        await parts.sync.consume(coreEvent(.message, message: "m1", author: "ann", text: "Привет", at: 100, authorName: "Анна Петрова"))
        await parts.sync.consume(coreEvent(.typing, author: "bob", text: "STICKER"))
        parts.clock.advance(1)
        await parts.sync.consume(coreEvent(.typing, author: "ann"))
        parts.clock.advance(1)
        // Повторный пуш меняет тип, но не место в очереди.
        await parts.sync.consume(coreEvent(.typing, author: "bob", text: "FILE"))
        let typing = await first(parts.chats.typing()) ?? [:]
        let list = typing["c1"] ?? []
        #expect(list.map(\.userId) == ["bob", "ann"])
        #expect(list.map(\.type) == ["FILE", nil])
        #expect(list.map(\.name) == [nil, "Анна Петрова"])
    }

    @Test("Недавние из поиска: новые первыми, без повторов, очистка")
    func recentSearches() async {
        let suite = "maxly.tests.\(UUID().uuidString)"
        let store = RecentSearchesStore(suiteName: suite)
        await store.add(chatId: "a")
        await store.add(chatId: "b")
        await store.add(chatId: "a")
        #expect(await store.recent() == ["a", "b"])
        await store.remove(chatId: "a")
        #expect(await store.recent() == ["b"])
        for index in 0..<30 { await store.add(chatId: "c\(index)") }
        #expect(await store.recent().count == RecentSearchesStore.limit)
        await store.clear()
        #expect(await store.recent().isEmpty)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test("Новый диалог из контактов появляется в списке с первым своим сообщением")
    func newDialogAppearsWithFirstMessage() async throws {
        let parts = try await makeParts(user: "10")
        let draft = try #require(DialogDraft.with(peerId: "3", me: "10", title: "Анна", avatarURL: URL(string: "https://a/b.jpg")))
        #expect(draft.chatId == String(Int64(10) ^ Int64(3)))
        await parts.chats.prepareDialog(draft)
        // Пока ничего не отправлено, диалога в списке нет.
        #expect(await chatRow(parts.chats, draft.chatId) == nil)

        try await parts.messages.send(text: "Привет", chatId: draft.chatId)
        let row = try #require(await chatRow(parts.chats, draft.chatId))
        #expect(row.title == "Анна")
        #expect(row.type == .private)
        #expect(row.preview == "Привет")
        #expect(row.avatarURL == URL(string: "https://a/b.jpg"))
        #expect(row.lastMessage?.isOutgoing == true)
    }

    @Test("Поиск на сервере: запрос без пробелов, пустой не отправляется, ошибка доходит")
    func serverSearch() async throws {
        let parts = try await makeParts()
        #expect(parts.chats.capabilities.contains(.serverSearch))
        let found = ChatSearchResult(id: "77", title: "Новости", subtitle: "@news", type: .channel)
        await parts.api.setSearchResult(.success([found]))
        #expect(try await parts.chats.search(query: "  новости ") == [found])
        #expect(try await parts.chats.search(query: "   ") == [])
        #expect(await parts.api.searchCalls == ["новости"])
        await parts.api.setSearchResult(.failure(.offline))
        await #expect(throws: MaxlyError.self) { try await parts.chats.search(query: "x") }
    }

    @Test("Поиск сообщений: запрос без пробелов, без повторов, ошибка доходит")
    func messageSearch() async throws {
        let parts = try await makeParts()
        let first = FoundMessage(chatId: "10", messageId: "1", senderId: "2", text: "привет")
        let other = FoundMessage(chatId: "11", messageId: "1", senderId: "2", text: "привет ещё")
        await parts.api.setMessageSearchResult(.success([first, other, first]))
        #expect(try await parts.chats.searchMessages(query: " привет ") == [first, other])
        #expect(try await parts.chats.searchMessages(query: "  ") == [])
        #expect(await parts.api.messageSearchCalls == ["привет"])
        await parts.api.setMessageSearchResult(.failure(.offline))
        await #expect(throws: MaxlyError.self) { try await parts.chats.searchMessages(query: "x") }
    }

    @Test("Найденное сообщение из ядра: время, без чата 0 и без пустого текста")
    func foundMessageMapping() {
        let found = CoreMapping.foundMessage(CoreFoundMessage(chatId: "10", messageId: "5", senderId: "2", text: " привет ", timeMs: 1_700_000_000_000))
        #expect(found == FoundMessage(chatId: "10", messageId: "5", senderId: "2", text: "привет", date: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(CoreMapping.foundMessage(CoreFoundMessage(chatId: "11", messageId: "6", text: "без времени"))?.date == nil)
        #expect(CoreMapping.foundMessage(CoreFoundMessage(chatId: "0", messageId: "7", text: "без чата")) == nil)
        #expect(CoreMapping.foundMessage(CoreFoundMessage(chatId: "12", messageId: "8", text: "  ")) == nil)
    }

    @Test("Найденный чат из ядра: тип, подпись, картинка и название по умолчанию")
    func searchMapping() {
        let channel = CoreMapping.searchResult(CoreSearchChat(id: "5", type: "CHANNEL", title: " Новости ", subtitle: "@news", avatarURL: "https://i/5"))
        #expect(channel == ChatSearchResult(id: "5", title: "Новости", subtitle: "@news", type: .channel, avatarURL: URL(string: "https://i/5")))
        let group = CoreSearchChat(id: "6", type: "CHAT", title: "", subtitle: " ")
        #expect(CoreMapping.searchResult(group) == ChatSearchResult(id: "6", title: "Группа", subtitle: nil, type: .group))
    }
}
