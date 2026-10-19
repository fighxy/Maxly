import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

private struct ServiceParts {
    let chats: ChatRepositoryImpl
    let messages: MessageRepositoryImpl
    let sync: SyncEngine
}

private func makeServiceParts(user: String = "1") async throws -> ServiceParts {
    let api = FakeMaxAPI()
    let stack = try SwiftDataStack(inMemory: true)
    let chats = ChatRepositoryImpl.make(stack: stack, api: api)
    let messages = MessageRepositoryImpl.make(stack: stack, api: api)
    let outbox = OutboxQueue(api: api, sleep: { _ in })
    await messages.attach(outbox: outbox)
    let sync = SyncEngine(outbox: outbox, chats: chats, messages: messages, pollInterval: .seconds(3600))
    await messages.setCurrentUser(id: user)
    return ServiceParts(chats: chats, messages: messages, sync: sync)
}

private func firstValue<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
    for await value in stream { return value }
    return nil
}

private func row(_ chats: ChatRepositoryImpl, _ id: String) async -> Chat? {
    await firstValue(chats.chats())?.first { $0.id == id }
}

private func groupChat(_ id: String, lastMessageId: String = "m1", preview: String? = "Привет", at seconds: TimeInterval = 100) -> ChatRecord {
    ChatRecord(
        id: id, title: "Дача", type: .group, lastMessageId: lastMessageId, unreadCount: 0,
        updatedAt: Date(timeIntervalSince1970: seconds), preview: preview
    )
}

private actor NoticeSink: IncomingMessageSink {
    private(set) var notices: [IncomingMessageNotice] = []
    func incoming(_ notice: IncomingMessageNotice) async { notices.append(notice) }
}

private func plain(_ id: String, chat: String, author: String, name: String, at seconds: TimeInterval) -> MessageRecord {
    MessageRecord(
        id: id, serverId: id, chatId: chat, authorId: author, text: "Привет",
        timestamp: Date(timeIntervalSince1970: seconds), status: .sent, authorName: name
    )
}

@Suite("Служебные сообщения: база и строка списка")
struct ServiceMessageDataTests {
    @Test("Пуш события: имена участников из базы, текст в строке списка без автора")
    func pushedEvent() async throws {
        let parts = try await makeServiceParts()
        try await parts.chats.upsert([groupChat("g1")])
        try await parts.messages.upsert([plain("m1", chat: "g1", author: "202", name: "Борис", at: 50)])

        await parts.sync.consume(CoreEvent(
            kind: .message, chatId: "g1", messageId: "m2", authorId: "101", text: "", title: "", chatType: "",
            timeMs: 200_000, unread: -1,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"add","userIds":[202,1]}]}"#,
            authorName: "Анна"
        ))

        let stored = try #require(await parts.messages.latest(chatId: "g1")?.domain)
        let notice = try #require(stored.content.service)
        #expect(notice.names?["202"] == "Борис")
        #expect(notice.viewerId == "1")
        #expect(stored.content.isService)
        #expect(ServiceText.text(notice, actorId: stored.authorId, actorName: stored.authorName) == "Анна добавил(а) Борис и вас")

        let chat = try #require(await row(parts.chats, "g1"))
        #expect(chat.preview == "Анна добавил(а) Борис и вас")
        #expect(chat.lastMessage?.media == .service)
    }

    @Test("Строка с сервера без текста берёт событие из сохранённого сообщения")
    func serverRowWithoutText() async throws {
        let parts = try await makeServiceParts()
        try await parts.messages.upsert([MessageRecord(
            id: "m9", serverId: "m9", chatId: "g2", authorId: "1", text: "",
            timestamp: Date(timeIntervalSince1970: 300), status: .sent,
            contentJSON: MessageContentCodec.encode(MessageContentCodec.decode(#"{"attaches":[{"_type":"CONTROL","event":"leave"}]}"#)),
            authorName: "Иван"
        )])
        try await parts.chats.upsert([groupChat("g2", lastMessageId: "m9", preview: nil, at: 300)])

        let chat = try #require(await row(parts.chats, "g2"))
        #expect(chat.preview == "Вы покинули чат")
        #expect(chat.lastMessage?.media == .service)
    }

    @Test("Последнее обычное сообщение строку не трогает")
    func plainRowUntouched() async throws {
        let parts = try await makeServiceParts()
        try await parts.messages.upsert([plain("m5", chat: "g3", author: "101", name: "Анна", at: 100)])
        try await parts.chats.upsert([groupChat("g3", lastMessageId: "m5", preview: nil, at: 100)])
        let chat = try #require(await row(parts.chats, "g3"))
        #expect(chat.preview == nil)
        #expect(chat.lastMessage?.media != .service)
    }

    @Test("Из истории CoreMessage служебное доходит до ленты")
    func fromHistory() {
        let record = CoreMapping.message(CoreMessage(
            id: "7", chatId: "d1", authorId: "101", text: "", timeMs: 1_000,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"hello"}]}"#, authorName: "Анна"
        ))
        let message = record.domain
        #expect(message.content.service?.event == "hello")
        #expect(message.content.previewMedia == .service)
        #expect(ServiceText.text(of: message.content, authorId: message.authorId, authorName: message.authorName) == "Анна теперь в MAX")
    }

    @Test("Вложение ядра: текст ядра для известного события, событие без фрагмента не теряется")
    func coreControl() {
        let created = CoreMapping.message(CoreMessage(
            id: "8", chatId: "g1", authorId: "101", text: "", timeMs: 1_000,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"new","chatType":"CHAT","title":"Дача"}]}"#, authorName: "Анна",
            control: CoreControl(event: "new", userIds: [], title: "Дача", fallbackText: "Анна создал(а) чат «Дача»")
        )).domain
        #expect(ServiceText.text(of: created.content, authorId: created.authorId, authorName: created.authorName) == "Анна создал(а) чат «Дача»")

        let bare = CoreMapping.message(CoreMessage(
            id: "9", chatId: "g1", authorId: "101", text: "", timeMs: 2_000, authorName: "Анна",
            control: CoreControl(event: "leave", userIds: [], title: nil, fallbackText: nil)
        )).domain
        #expect(bare.content.isService)
        #expect(ServiceText.text(of: bare.content, authorId: bare.authorId, authorName: bare.authorName) == "Анна покинул(а) чат")

        let pin = CoreMapping.message(CoreMessage(
            id: "10", chatId: "g1", authorId: "101", text: "", timeMs: 3_000,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"pin","pinnedMessage":{"id":7,"text":"Сбор"}}]}"#,
            control: CoreControl(event: "pin")
        )).domain
        #expect(pin.content.pin != nil)
        #expect(pin.content.service == nil)
    }

    @Test("Текст сервера из вложения ядра: событие без type и без фрагмента не теряется")
    func coreControlServerText() {
        let server = CoreMapping.message(CoreMessage(
            id: "11", chatId: "g1", authorId: "101", text: "", timeMs: 4_000, authorName: "Анна",
            control: CoreControl(event: "futureEvent", fallbackText: "Сервер: новое событие", shortMessage: "Сервер: новое событие")
        )).domain
        #expect(server.content.isService)
        #expect(server.content.service?.text == "Сервер: новое событие")
        #expect(ServiceText.text(of: server.content, authorId: server.authorId, authorName: server.authorName) == "Сервер: новое событие")

        let silent = CoreMapping.message(CoreMessage(
            id: "12", chatId: "g1", authorId: "101", text: "", timeMs: 5_000, authorName: "Анна",
            control: CoreControl(event: "")
        )).domain
        #expect(silent.content.isService)
        #expect(ServiceText.text(of: silent.content, authorId: silent.authorId, authorName: silent.authorName) == ServiceText.fallback)
    }

    @Test("Пуш с вложением ядра: в строке и уведомлении текст ядра, «теперь в MAX» — тоже ядра")
    func pushedCoreText() async throws {
        let parts = try await makeServiceParts()
        let sink = NoticeSink()
        await parts.sync.attachIncoming(sink)
        try await parts.chats.upsert([groupChat("g1")])
        await parts.sync.consume(CoreEvent(
            kind: .message, chatId: "g1", messageId: "m2", authorId: "101", text: "", title: "", chatType: "",
            timeMs: 200_000, unread: -1,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"add","userIds":[404,405]}]}"#,
            authorName: "Анна",
            control: CoreControl(event: "add", userIds: ["404", "405"], fallbackText: "Анна добавил(а) Глеб и Дину")
        ))
        let chat = try #require(await row(parts.chats, "g1"))
        #expect(chat.preview == "Анна добавил(а) Глеб и Дину")
        #expect(chat.lastMessage?.media == .service)
        // Из событий групп уведомляет только «теперь в MAX».
        #expect(await sink.notices.isEmpty)

        try await parts.chats.upsert([ChatRecord(
            id: "d1", title: "Анна", type: .private, lastMessageId: "m1", unreadCount: 0,
            updatedAt: Date(timeIntervalSince1970: 100), preview: "Привет"
        )])
        await parts.sync.consume(CoreEvent(
            kind: .message, chatId: "d1", messageId: "m3", authorId: "101", text: "", title: "", chatType: "",
            timeMs: 300_000, unread: -1,
            contentJSON: #"{"attaches":[{"_type":"CONTROL","event":"new","chatType":"DIALOG"}]}"#,
            authorName: "",
            control: CoreControl(event: "new", fallbackText: "Анна Петрова теперь в MAX")
        ))
        #expect(try #require(await row(parts.chats, "d1")).preview == "Анна Петрова теперь в MAX")
        let notices = await sink.notices
        #expect(notices.map(\.text) == ["Анна Петрова теперь в MAX"])
    }

    @Test("Правка служебного из пуша: строка берёт текст ядра")
    func editedCoreText() async throws {
        let parts = try await makeServiceParts()
        try await parts.chats.upsert([groupChat("g1", lastMessageId: "m4", preview: "Анна изменил(а) название на «Дача»", at: 200)])
        let control = #"{"attaches":[{"_type":"CONTROL","event":"title","title":"Дача 2027"}]}"#
        await parts.sync.consume(CoreEvent(
            kind: .message, chatId: "g1", messageId: "m4", authorId: "101", text: "", title: "", chatType: "",
            timeMs: 200_000, unread: -1, contentJSON: control, authorName: "Анна",
            control: CoreControl(event: "title", title: "Дача 2027", fallbackText: "Анна изменил(а) название на «Дача 2027»")
        ))
        await parts.sync.consume(CoreEvent(
            kind: .edited, chatId: "g1", messageId: "m4", authorId: "101", text: "", title: "", chatType: "",
            timeMs: 200_000, unread: -1, contentJSON: control, authorName: "Анна", updateTimeMs: 210_000,
            control: CoreControl(event: "title", title: "Дача 2027", fallbackText: "Сервер: название изменено")
        ))
        #expect(try #require(await row(parts.chats, "g1")).preview == "Сервер: название изменено")
    }

    @Test("Строка списка с lastControl: текст ядра без сообщения в базе")
    func chatRowLastControl() async throws {
        func core(_ control: CoreControl?, lastText: String = "") -> ChatRecord {
            var chat = CoreChat(id: "g5", title: "Дача", type: "CHAT", lastMessageId: "m7", lastText: lastText, updatedAtMs: 500_000, unread: 0)
            chat.lastControl = control
            return CoreMapping.chat(chat)
        }
        let named = core(CoreControl(event: "leave", fallbackText: "Борис покинул(а) чат"))
        #expect(named.preview == "Борис покинул(а) чат")
        #expect(named.lastMedia == .service)
        #expect(core(CoreControl(event: "system"), lastText: "Вход с нового устройства").preview == "Вход с нового устройства")
        #expect(core(CoreControl(event: "system")).preview == ServiceText.fallback)
        #expect(core(CoreControl(event: "futureEvent", message: "Сервер: новое событие")).preview == "Сервер: новое событие")
        let pin = core(CoreControl(event: "pin"), lastText: "")
        #expect(pin.preview == nil)
        #expect(pin.lastMedia == nil)
        #expect(core(nil, lastText: "Привет").preview == "Привет")

        let parts = try await makeServiceParts()
        try await parts.chats.upsert([named])
        let chat = try #require(await row(parts.chats, "g5"))
        #expect(chat.preview == "Борис покинул(а) чат")
        #expect(chat.lastMessage?.media == .service)
    }

    @Test("Текст ядра важнее своего, и у new личного чата")
    func coreTextWins() {
        var notice = ServiceNotice(event: "new", chatType: "DIALOG", viewerId: "1")
        #expect(ServiceText.text(notice, actorId: "101", actorName: "Анна") == "Анна теперь в MAX")
        notice.coreText = "Анна Петрова теперь в MAX"
        #expect(ServiceText.text(notice, actorId: "101", actorName: "Анна") == "Анна Петрова теперь в MAX")
        // Без текста ядра и без имени — безлично, как пишет ядро.
        #expect(ServiceText.text(ServiceNotice(event: "add", userIds: ["202"]), actorId: "101", actorName: "") == "Добавлены участники")
        #expect(ServiceText.text(ServiceNotice(event: "new", title: "Дача", chatType: "CHAT"), actorId: "101", actorName: "") == "Создан чат «Дача»")
        #expect(ServiceText.text(ServiceNotice(event: "botStarted", viewerId: "1"), actorId: "101", actorName: "Анна") == "Бот запущен")
    }
}
