import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Репозиторий сообщений со списком «Кем прочитано».
private actor ReaderMessages: MessageRepository {
    var available = true
    var readers: [MessageReader] = []
    var error: MaxlyError?
    private(set) var calls: [String] = []

    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) {}
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) {}
    func retry(messageId: String) async throws(MaxlyError) {}
    func reactionCatalog() async -> [String] { [] }

    func readersAvailable(chatId: String) async -> Bool { available }

    func messageReaders(messageId: String) async throws(MaxlyError) -> [MessageReader] {
        calls.append(messageId)
        if let error { throw error }
        return readers
    }

    func set(available: Bool = true, readers: [MessageReader] = [], error: MaxlyError? = nil) {
        self.available = available
        self.readers = readers
        self.error = error
    }
}

@Suite("Сведения о сообщении")
@MainActor
struct MessageInfoViewModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Novosibirsk")!
        return calendar
    }

    /// 8 октября 2026, 16:00 по Новосибирску.
    private let now = Date(timeIntervalSince1970: 1_791_450_000)

    private func message(
        id: String = "500",
        serverId: String? = "500",
        chatId: String = "-100",
        author: String = "me",
        status: MessageStatus = .sent,
        at date: Date? = nil,
        content: MessageContent = .empty,
        isRead: Bool = false,
        editedAt: Date? = nil
    ) -> Message {
        Message(
            id: id, serverId: serverId, chatId: chatId, authorId: author, text: "Привет",
            timestamp: date ?? now.addingTimeInterval(-3600), status: status, content: content,
            isRead: isRead, editedAt: editedAt
        )
    }

    private func model(_ message: Message, chatType: ChatType, isOwn: Bool = true, repository: ReaderMessages) -> MessageInfoViewModel {
        let now = now
        return MessageInfoViewModel(message: message, chatType: chatType, isOwn: isOwn, repository: repository, now: { now }, calendar: calendar)
    }

    @Test("Время: сегодня, вчера, день месяца, другой год")
    func moments() {
        #expect(MessageInfoViewModel.moment(now.addingTimeInterval(-3600), now: now, calendar: calendar) == "сегодня в 15:00")
        #expect(MessageInfoViewModel.moment(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "вчера в 16:00")
        #expect(MessageInfoViewModel.moment(now.addingTimeInterval(-5 * 86_400), now: now, calendar: calendar) == "3 октября в 16:00")
        #expect(MessageInfoViewModel.moment(now.addingTimeInterval(-400 * 86_400), now: now, calendar: calendar) == "3 сентября 2025 в 16:00")
    }

    @Test("Пункт есть только у сообщений на сервере")
    func availability() {
        #expect(MessageInfoViewModel.isAvailable(for: message()))
        #expect(!MessageInfoViewModel.isAvailable(for: message(status: .sending)))
        #expect(!MessageInfoViewModel.isAvailable(for: message(status: .failed)))
        #expect(!MessageInfoViewModel.isAvailable(for: message(id: "local-1", serverId: nil)))
        let model = ChatViewModel(chatId: "-100", currentUserId: "me", messages: ReaderMessages())
        model.showMessageInfo(message(status: .sending), chatType: .group)
        #expect(model.messageInfo == nil)
        model.showMessageInfo(message(author: "anna"), chatType: .group)
        #expect(model.messageInfo?.isOwn == false)
    }

    @Test("Отправлено, изменено, переслано")
    func rows() {
        let repository = ReaderMessages()
        let forwarded = MessageContent(forward: MessageForward(authorName: "Иван Петров", text: "Исходник"), edited: true)
        let edited = model(message(content: forwarded, editedAt: now.addingTimeInterval(-600)), chatType: .group, repository: repository)
        #expect(edited.sentText == "сегодня в 15:00")
        #expect(edited.editedText == "сегодня в 15:50")
        #expect(edited.forwardedFrom == "Иван Петров")

        let noTime = model(message(content: MessageContent(edited: true)), chatType: .group, repository: repository)
        #expect(noTime.editedText == MessageInfoViewModel.editedWithoutTime)
        #expect(noTime.forwardedFrom == nil)

        let plain = model(message(), chatType: .group, repository: repository)
        #expect(plain.editedText == nil)
    }

    @Test("Личный чат: «Прочитано»/«Доставлено» только у своего, не в «Избранном»")
    func privateStatus() {
        let repository = ReaderMessages()
        #expect(model(message(chatId: "77", isRead: true), chatType: .private, repository: repository).readStatus == .read)
        #expect(model(message(chatId: "77"), chatType: .private, repository: repository).readStatus == .delivered)
        #expect(model(message(chatId: "77", author: "anna", isRead: true), chatType: .private, isOwn: false, repository: repository).readStatus == nil)
        #expect(model(message(chatId: Chat.savedMessagesId, isRead: true), chatType: .private, repository: repository).readStatus == nil)
        #expect(model(message(isRead: true), chatType: .group, repository: repository).readStatus == nil)
        #expect(PrivateReadStatus.read.title == "Прочитано")
        #expect(PrivateReadStatus.delivered.title == "Доставлено")
    }

    @Test("Группа: загрузка, список, пусто, ошибка")
    func groupReaders() async {
        let repository = ReaderMessages()
        let anna = MessageReader(userId: "7", reaction: "👍", readMark: nil, name: "Анна")
        let boris = MessageReader(userId: "8", readMark: now.addingTimeInterval(-60).timeIntervalSince1970Ms)
        await repository.set(readers: [anna, boris])
        let info = model(message(), chatType: .group, repository: repository)
        #expect(info.readers == .hidden)
        await info.load()
        #expect(info.readers == .loaded([anna, boris]))
        #expect(await repository.calls == ["500"])
        #expect(MessageInfoViewModel.name(of: boris) == "Пользователь 8")
        #expect(info.readerDetail(anna) == nil)
        #expect(info.readerDetail(boris) == "Прочитано · сегодня в 15:59")

        await repository.set(readers: [])
        await info.load()
        #expect(info.readers == .loaded([]))
        #expect(MessageInfoViewModel.emptyReaders == "Пока никто не прочитал")

        await repository.set(error: .networkUnavailable)
        await info.load()
        #expect(info.readers == .failed("Не удалось загрузить список"))
    }

    @Test("Нет раздела: чат без списка, личный чат, канал")
    func hiddenReaders() async {
        let repository = ReaderMessages()
        await repository.set(available: false)
        let big = model(message(), chatType: .group, repository: repository)
        await big.load()
        #expect(big.readers == .hidden)

        await repository.set(available: true)
        let dialog = model(message(chatId: "77"), chatType: .private, repository: repository)
        await dialog.load()
        #expect(dialog.readers == .hidden)
        let channel = model(message(), chatType: .channel, repository: repository)
        await channel.load()
        #expect(channel.readers == .hidden)
        #expect(await repository.calls.isEmpty)
    }
}

private extension Date {
    var timeIntervalSince1970Ms: Int64 { Int64(timeIntervalSince1970 * 1000) }
}
