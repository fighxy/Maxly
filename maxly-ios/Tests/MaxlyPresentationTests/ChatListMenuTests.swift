import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private let menuNow = Date(timeIntervalSince1970: 1_790_683_200)

private final class MenuFolders: FolderRepository, @unchecked Sendable {
    var list: [ServerFolder] = [
        ServerFolder(id: "all", title: "Все", isAllChats: true),
        ServerFolder(id: "w", title: "Работа", chatIds: ["2"]),
    ]
    var calls: [String] = []

    func folders() -> AsyncStream<[ServerFolder]> {
        let list = list
        return AsyncStream { $0.yield(list) }
    }
    func reload() async throws(MaxlyError) {}
    func create(title: String, chatIds: [String], filters: [String]) async throws(MaxlyError) {}
    func rename(folderId: String, title: String) async throws(MaxlyError) {}
    func setChats(folderId: String, chatIds: [String]) async throws(MaxlyError) {
        calls.append("\(folderId) \(chatIds.joined(separator: ","))")
    }
    func delete(folderId: String) async throws(MaxlyError) {}
    func reorder(_ folderIds: [String]) async throws(MaxlyError) {}
}

private actor Blocker: ProfileActionsRepository {
    private(set) var blocked: [String] = []
    func members(chatId: String) async throws(MaxlyError) -> [ProfileMember] { [] }
    func commonChats(userId: String) async throws(MaxlyError) -> [CommonChat] { [] }
    func complaintReasons(for target: ComplaintTarget) async throws(MaxlyError) -> [ComplaintReason] { [] }
    func complain(about target: ComplaintTarget, reasonId: Int) async throws(MaxlyError) -> Bool { false }
    func isBlocked(userId: String) async throws(MaxlyError) -> Bool { false }
    func setBlocked(userId: String, blocked: Bool) async throws(MaxlyError) {
        if blocked { self.blocked.append(userId) }
    }
    func membersPage(chatId: String, marker: Int64) async throws(MaxlyError) -> ChatMembersPage {
        throw .invalidRequest
    }
}

@Suite("Меню строки списка чатов")
@MainActor
struct ChatListMenuTests {
    private let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))

    private func item(_ value: Chat) -> ChatListItem {
        formatter.item(for: value, now: menuNow)
    }

    private let all: ChatListCapabilities = [.pin, .markUnread, .mute, .delete, .archive]

    @Test("Порядок как в Max, красные — блокировка и удаление")
    func order() {
        let folders = [ChatListMenu.FolderChoice(id: "w", title: "Работа", contains: false)]
        let entries = ChatListMenu.entries(item: item(chat("1", at: 1, type: .private)), folders: folders, capabilities: all, hasStories: true, canBlock: true)
        #expect(entries.map(\.title) == [
            "Добавить в папку", "Закрепить", "Отметить непрочитанным", "Отключить уведомления",
            "Стереть переписку", "Скрыть истории автора", "Заблокировать", "Удалить чат",
        ])
        #expect(entries.map(\.isDanger) == [false, false, false, false, false, false, true, true])
    }

    @Test("У группы нет блокировки, без папок нет подменю")
    func group() {
        var value = chat("1", at: 1, unread: 2)
        value.isMuted = true
        value.pinOrder = 0
        let entries = ChatListMenu.entries(item: item(value), folders: [], capabilities: all, canBlock: true)
        #expect(entries.map(\.title) == ["Открепить", "Отметить прочитанным", "Включить уведомления", "Стереть переписку", "Удалить чат"])
    }

    @Test("«Избранное» не блокируют и не скрывают")
    func saved() {
        let entries = ChatListMenu.entries(item: item(chat(Chat.savedMessagesId, at: 1, type: .private)), folders: [], capabilities: all, hasStories: true, canBlock: true)
        #expect(!entries.contains(.block) && !entries.contains(.hideStories))
    }

    @Test("Сроки отключения уведомлений")
    func durations() {
        let ms: Int64 = 1_790_683_200_000
        #expect(ChatListMenu.MuteFor.allCases.map(\.title) == ["На 1 час", "На 4 часа", "На 1 день", "Навсегда"])
        #expect(ChatListMenu.MuteFor.hour.until(now: menuNow) == ms + 3_600_000)
        #expect(ChatListMenu.MuteFor.fourHours.until(now: menuNow) == ms + 14_400_000)
        #expect(ChatListMenu.MuteFor.day.until(now: menuNow) == ms + 86_400_000)
        #expect(ChatListMenu.MuteFor.forever.until(now: menuNow) == -1)
        #expect(ChatListMenu.MuteFor.allCases.filter(\.isDanger) == [.forever])
    }

    @Test("Собеседник из id диалога")
    func peer() {
        #expect(ChatListMenu.peer(chatId: String(42 ^ 7), myId: "7") == "42")
        #expect(ChatListMenu.peer(chatId: Chat.savedMessagesId, myId: "7") == nil)
    }

    private func makeModel(folders: MenuFolders, actions: Blocker) -> (ChatListViewModel, FakeChatRepository) {
        let repository = FakeChatRepository(capabilities: all)
        let model = ChatListViewModel(chats: repository, formatter: formatter, searchDelay: .zero, now: { menuNow })
        model.folderEditor = folders
        model.profileActions = actions
        model.currentUserId = "7"
        model.activate()
        return (model, repository)
    }

    @Test("Срок уходит в репозиторий")
    func muteFor() async {
        let (model, repository) = makeModel(folders: MenuFolders(), actions: Blocker())
        repository.emit([chat("1", at: 1)])
        #expect(await eventually { model.items.count == 1 })
        await model.muteFor(chatId: "1", .fourHours)
        await model.muteFor(chatId: "1", .forever)
        #expect(await repository.actions == ["mute-until 1 \(1_790_683_200_000 + 14_400_000)", "mute-until 1 -1"])
    }

    @Test("Папка: добавить и убрать")
    func folders() async {
        let folders = MenuFolders()
        let (model, repository) = makeModel(folders: folders, actions: Blocker())
        repository.emit([chat("1", at: 1), chat("2", at: 2)])
        #expect(await eventually { !model.folderChoices(chatId: "1").isEmpty })
        #expect(model.folderChoices(chatId: "1") == [ChatListMenu.FolderChoice(id: "w", title: "Работа", contains: false)])
        await model.toggleFolder(chatId: "1", folderId: "w")
        #expect(model.notice == "Чат добавлен в «Работа»")
        await model.toggleFolder(chatId: "2", folderId: "w")
        #expect(model.notice == "Чат убран из «Работа»")
        await model.toggleFolder(chatId: "1", folderId: "all")
        #expect(folders.calls == ["w 2,1", "w "])
    }

    @Test("Блокировка собеседника личного чата")
    func block() async {
        let actions = Blocker()
        let (model, repository) = makeModel(folders: MenuFolders(), actions: actions)
        let dialog = String(42 ^ 7)
        repository.emit([chat(dialog, at: 1, type: .private), chat("g", at: 2)])
        #expect(await eventually { model.items.count == 2 })
        await model.block(chatId: dialog)
        await model.block(chatId: "g")
        #expect(await actions.blocked == ["42"])
        #expect(model.notice == "Пользователь заблокирован")
    }
}
