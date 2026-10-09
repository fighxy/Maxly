import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Репозиторий, который записывает удаление, пересылку и отправку.
private actor SelectionMessages: MessageRepository {
    struct Deletion: Equatable {
        var ids: [String]
        var forEveryone: Bool
    }

    private(set) var deletions: [Deletion] = []
    private(set) var log: [String] = []
    var failForwardAt: Int?
    /// id, которые «сервер» отказался удалить.
    var refused: Set<String> = []

    func setFailForward(at index: Int?) { failForwardAt = index }
    func setRefused(_ ids: Set<String>) { refused = ids }
    /// Ответ «ядра» на `deletePlan`; `nil` — не умеет.
    var plan: MessageSelectionRules.DeleteOptions?
    private(set) var planRequests: [[String]] = []
    func setPlan(_ options: MessageSelectionRules.DeleteOptions?) { plan = options }

    func deletePlan(messageIds: [String], chatId: String) async -> MessageSelectionRules.DeleteOptions? {
        planRequests.append(messageIds)
        return plan
    }

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { $0.finish() } }
    func loadOlder(chatId: String) async throws(MaxlyError) {}
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}

    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {
        log.append("comment \(chatId) \(text)")
    }

    func delete(messageIds: [String], chatId: String, forEveryone: Bool) async throws(MaxlyError) {
        deletions.append(Deletion(ids: messageIds, forEveryone: forEveryone))
    }

    func deleteSelection(messageIds: [String], chatId: String, forEveryone: Bool) async throws(MaxlyError) -> [String] {
        deletions.append(Deletion(ids: messageIds, forEveryone: forEveryone))
        return messageIds.filter(refused.contains)
    }

    func forward(messageId: String, from chatId: String, to targetChatId: String) async throws(MaxlyError) {
        if let failForwardAt, log.count == failForwardAt { throw .networkUnavailable }
        log.append("forward \(targetChatId) \(messageId)")
    }
}

@MainActor
@Suite("Выбор сообщений: модель")
struct MessageSelectionModelTests {
    let base = Date(timeIntervalSince1970: 1_791_455_400)

    func message(_ id: String, author: String = "1", offset: TimeInterval, text: String = "текст", status: MessageStatus = .sent,
                 name: String = "", content: MessageContent = .empty) -> Message {
        Message(id: id, serverId: status == .sent ? id : nil, chatId: "5", authorId: author, text: text,
                timestamp: base.addingTimeInterval(offset), status: status, content: content, authorName: name)
    }

    @Test("«Выбрать» включает режим с этим сообщением, касания отмечают и снимают")
    func toggling() {
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: SelectionMessages())
        let a = message("10", offset: 0)
        let b = message("11", offset: 1)
        model.begin(with: a)
        #expect(model.isActive)
        model.toggle(b)
        #expect(model.title(in: [a, b]) == "Выбрано: 2")
        model.toggle(a)
        #expect(model.selected(in: [a, b]).map(\.id) == ["11"])
        model.cancel()
        #expect(!model.isActive && model.selectedIds.isEmpty)
    }

    @Test("Служебное о закрепе не выбирается")
    func pinNotSelectable() {
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: SelectionMessages())
        let pin = message("10", offset: 0, content: MessageContent(pin: PinNotice(messageId: "3", preview: "x")))
        model.begin(with: pin)
        #expect(!model.isActive)
    }

    @Test("Удаление: все id одним запросом, переключатель «у всех» по правилам")
    func deleteAll() async {
        let repo = SelectionMessages()
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: repo)
        model.chatType = .private
        model.editTimeout = .seconds(86_400)
        model.now = { [base] in base.addingTimeInterval(60) }
        let own = message("10", offset: 0)
        let peer = message("11", author: "5", offset: 1)
        model.begin(with: own)
        await model.requestDelete(in: [own])
        #expect(model.deleteRequest?.options.showsForEveryone == true)
        model.toggle(peer)
        await model.requestDelete(in: [own, peer])
        guard let request = model.deleteRequest else { Issue.record("нет подтверждения"); return }
        #expect(request.options.showsForEveryone == false)
        #expect(request.title == "Удалить 2 сообщения?")
        await model.confirmDelete(request, forEveryone: true)
        #expect(await repo.deletions == [.init(ids: ["10", "11"], forEveryone: false)])
        #expect(!model.isActive)
    }

    @Test("Диалог удаления строит ядро: его положение переключателя вместо своего")
    func corePlan() async {
        let repo = SelectionMessages()
        await repo.setPlan(.init(canDelete: true, showsForEveryone: true, forcesForEveryone: false, forEveryoneByDefault: false))
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: repo)
        let peer = message("11", author: "5", offset: 1)
        model.begin(with: peer)
        await model.requestDelete(in: [peer])
        #expect(await repo.planRequests.last == ["11"])
        #expect(model.deleteRequest?.options.showsForEveryone == true)
        #expect(model.deleteRequest?.options.forEveryoneByDefault == false)

        await repo.setPlan(.init(canDelete: false, showsForEveryone: false, forcesForEveryone: false, forEveryoneByDefault: false))
        model.deleteRequest = nil
        await model.requestDelete(in: [peer])
        #expect(model.deleteRequest == nil)
    }

    @Test("Сервер удалил не всё: отказанные остаются, об этом плашка")
    func partialDelete() async {
        let repo = SelectionMessages()
        await repo.setRefused(["11"])
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: repo)
        var notices: [String] = []
        var deleted: [String] = []
        model.onNotice = { notices.append($0) }
        model.onDeleted = { deleted = $0 }
        let a = message("10", offset: 0)
        let b = message("11", offset: 1)
        model.begin(with: a)
        model.toggle(b)
        await model.requestDelete(in: [a, b])
        guard let request = model.deleteRequest else { Issue.record("нет подтверждения"); return }
        await model.confirmDelete(request, forEveryone: false)
        #expect(deleted == ["10"])
        #expect(notices == ["Не удалось удалить: 1 сообщение"])
    }

    @Test("«Избранное» стирается целиком, канал с правами — только у всех, подписчик — нельзя")
    func savedAndChannel() async {
        let repo = SelectionMessages()
        let saved = MessageSelectionModel(chatId: Chat.savedMessagesId, currentUserId: "1", repository: repo)
        let note = message("10", offset: 0)
        saved.begin(with: note)
        await saved.requestDelete(in: [note])
        if let request = saved.deleteRequest { await saved.confirmDelete(request, forEveryone: false) }
        #expect(await repo.deletions.last?.forEveryone == true)

        let channel = MessageSelectionModel(chatId: "-20", currentUserId: "1", repository: repo)
        channel.chatType = .channel
        let post = message("30", author: "9", offset: 0)
        channel.begin(with: post)
        #expect(channel.deleteOptions(in: [post]).canDelete == false)
        channel.isAdmin = true
        #expect(channel.deleteOptions(in: [post]).forcesForEveryone)
    }

    @Test("Пересылка: от старых к новым, комментарий первым, по запросу на чат")
    func forwardOrder() async {
        let repo = SelectionMessages()
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: repo)
        var notices: [String] = []
        model.onNotice = { notices.append($0) }
        let newer = message("20", offset: 10)
        let older = message("10", offset: 0)
        model.begin(with: newer)
        model.toggle(older)
        model.requestForward(in: [older, newer])
        let batch = model.forwardBatch ?? []
        #expect(batch.map(\.id) == ["10", "20"])
        let done = await model.forward(batch, to: ["A", "B"], comment: " смотри ")
        #expect(done == 6)
        #expect(await repo.log == [
            "comment A смотри", "comment B смотри",
            "forward A 10", "forward B 10", "forward A 20", "forward B 20",
        ])
        #expect(notices == ["Переслано: 2 сообщения в 2 чата"])
    }

    @Test("Пересылка останавливается на ошибке и сообщает о ней")
    func forwardFailure() async {
        let repo = SelectionMessages()
        await repo.setFailForward(at: 1)
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: repo)
        var errors: [MaxlyError] = []
        model.onError = { errors.append($0) }
        let a = message("10", offset: 0)
        let b = message("11", offset: 1)
        let done = await model.forward([a, b], to: ["A"])
        #expect(done == 1)
        #expect(errors == [.networkUnavailable])
    }

    @Test("Неотправленное не пересылается")
    func unsentNotForwarded() {
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: SelectionMessages())
        let pending = message("local-1", offset: 0, status: .sending)
        model.begin(with: pending)
        #expect(!model.canForward(in: [pending]))
        #expect(model.deleteOptions(in: [pending]).canDelete)
    }

    @Test("Копирование: одно — текст, несколько — блоки с именем и временем; свои — «Вы»")
    func copying() {
        let model = MessageSelectionModel(chatId: "5", currentUserId: "1", repository: SelectionMessages())
        model.timeZone = TimeZone(identifier: "Europe/Moscow")!
        model.peerName = "Анна"
        let mine = message("11", offset: 60, text: "Как дела?")
        let peer = message("10", author: "5", offset: 0, text: "Привет")
        let photo = message("12", author: "5", offset: 120, text: "", name: "Анна Петрова",
                            content: MessageContent(attachments: [.photo(PhotoContent(id: "p", url: nil, width: 1, height: 1))]))
        model.begin(with: peer)
        #expect(model.copyText(in: [peer]) == "Привет")
        model.toggle(mine)
        model.toggle(photo)
        #expect(model.copyText(in: [peer, mine, photo]) ==
            "Анна, [08.10.2026 13:30]\nПривет\n\nВы, [08.10.2026 13:31]\nКак дела?\n\nАнна Петрова, [08.10.2026 13:32]\nФото")
        var copied: String?
        model.copy(in: [peer, mine, photo]) { copied = $0 }
        #expect(copied?.hasPrefix("Анна") == true)
        #expect(!model.isActive)
    }
}
