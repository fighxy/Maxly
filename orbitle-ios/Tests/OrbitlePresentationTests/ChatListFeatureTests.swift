import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@MainActor
private func makeFeatureList(
    capabilities: ChatListCapabilities = [.pin, .reorderPins, .markUnread],
    recents: FakeRecentSearches? = nil,
    pinLimit: Int = ChatListViewModel.defaultPinLimit
) -> (ChatListViewModel, FakeChatRepository) {
    let repository = FakeChatRepository(capabilities: capabilities)
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    let model = ChatListViewModel(
        chats: repository,
        recentSearches: recents,
        formatter: formatter,
        pinLimit: pinLimit,
        searchDelay: .zero,
        now: { Date(timeIntervalSince1970: 1_790_683_200) }
    )
    model.activate()
    return (model, repository)
}

private func pinned(_ id: String, order: Int, at seconds: TimeInterval = 1) -> Chat {
    var value = chat(id, at: seconds)
    value.pinOrder = order
    return value
}

@Suite("Список чатов: закреплённые")
@MainActor
struct ChatListPinTests {
    @Test("Закреплённые сверху в своём порядке, остальные по времени")
    func order() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("new", at: 900), pinned("p2", order: 2), pinned("p1", order: 1), chat("old", at: 100)])
        #expect(await eventually { model.items.count == 4 })
        #expect(model.items.map(\.id) == ["p1", "p2", "new", "old"])
        #expect(model.items[0].isPinned && model.items[0].showsPin)
        #expect(!model.items[2].isPinned)
        #expect(model.pinnedCount == 2)
    }

    @Test("Закрепление сразу поднимает строку и не откатывается, пока снимок не догнал")
    func optimisticPin() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("a", at: 900), chat("b", at: 100)])
        #expect(await eventually { model.items.count == 2 })
        let gate = Gate()
        await repository.set(actionGate: gate)
        let pin = Task { await model.togglePin(chatId: "b") }
        #expect(await eventually { model.items.first?.id == "b" })
        // Посторонний снимок до записи в базу: строка остаётся наверху.
        repository.emit([chat("a", at: 950), chat("b", at: 100)])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.items.first?.id == "b")
        await gate.open()
        await pin.value
        repository.emit([chat("a", at: 950), pinned("b", order: 0, at: 100)])
        #expect(await eventually { model.items.map(\.id) == ["b", "a"] })
        #expect(await repository.actions == ["pin b"])
    }

    @Test("Ошибка закрепления возвращает строку на место и показывается")
    func pinFailure() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("a", at: 900), chat("b", at: 100)])
        #expect(await eventually { model.items.count == 2 })
        await repository.set(actionError: .server(code: "pin.limit"))
        await model.togglePin(chatId: "b")
        #expect(model.items.map(\.id) == ["a", "b"])
        #expect(model.error == .server(code: "pin.limit"))
    }

    @Test("Лимит закреплённых проверяется до запроса")
    func pinLimit() async {
        let (model, repository) = makeFeatureList(pinLimit: 2)
        repository.emit([pinned("p1", order: 1), pinned("p2", order: 2), chat("c", at: 5)])
        #expect(await eventually { model.items.count == 3 })
        await model.togglePin(chatId: "c")
        #expect(model.error == .rejected("Можно закрепить не больше 2 чатов. Открепите один из них"))
        #expect(await repository.actions.isEmpty)
        await model.togglePin(chatId: "p1")
        #expect(await repository.actions == ["unpin p1"])
    }

    @Test("Без поддержки закрепления действие не выполняется")
    func pinUnsupported() async {
        let (model, repository) = makeFeatureList(capabilities: [])
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.items.count == 1 })
        await model.togglePin(chatId: "a")
        #expect(await repository.actions.isEmpty)
        #expect(!model.canReorderPinned)
    }

    @Test("Перетаскивание закреплённых в режиме правки")
    func reorder() async {
        let (model, repository) = makeFeatureList()
        repository.emit([pinned("p1", order: 0), pinned("p2", order: 1), pinned("p3", order: 2), chat("c", at: 5)])
        #expect(await eventually { model.items.count == 4 })
        #expect(!model.canReorderPinned)
        model.isEditing = true
        #expect(model.canReorderPinned)
        await model.movePinned(from: IndexSet(integer: 0), to: 3)
        #expect(model.items.map(\.id) == ["p2", "p3", "p1", "c"])
        #expect(await repository.actions == ["order p2,p3,p1"])
        // Старый снимок не откатывает порядок, новый подтверждает его.
        repository.emit([pinned("p1", order: 0), pinned("p2", order: 1), pinned("p3", order: 2), chat("c", at: 6)])
        try? await Task.sleep(for: .milliseconds(20))
        #expect(model.items.map(\.id) == ["p2", "p3", "p1", "c"])
        repository.emit([pinned("p2", order: 0), pinned("p3", order: 1), pinned("p1", order: 2), chat("c", at: 6)])
        #expect(await eventually { model.items.map(\.id) == ["p2", "p3", "p1", "c"] })
    }

    @Test("Ошибка сервера при перестановке возвращает прежний порядок")
    func reorderFailure() async {
        let (model, repository) = makeFeatureList()
        repository.emit([pinned("p1", order: 0), pinned("p2", order: 1), chat("c", at: 5)])
        #expect(await eventually { model.items.count == 3 })
        model.isEditing = true
        await repository.set(actionError: .networkUnavailable)
        await model.movePinned(from: IndexSet(integer: 1), to: 0)
        #expect(await repository.actions == ["order p2,p1"])
        #expect(model.items.map(\.id) == ["p1", "p2", "c"])
        #expect(model.error == .networkUnavailable)
    }

    @Test("Ошибка открепления оставляет чат закреплённым")
    func unpinFailure() async {
        let (model, repository) = makeFeatureList()
        repository.emit([pinned("p1", order: 0), chat("c", at: 5)])
        #expect(await eventually { model.items.count == 2 })
        await repository.set(actionError: .networkUnavailable)
        await model.togglePin(chatId: "p1")
        #expect(await repository.actions == ["unpin p1"])
        #expect(model.items.map(\.id) == ["p1", "c"])
        #expect(model.items.first?.isPinned == true)
    }

    @Test("Закрепление с другого устройства сразу меняет список")
    func remotePins() async {
        let (model, repository) = makeFeatureList()
        repository.emit([pinned("p1", order: 0), chat("a", at: 900), chat("b", at: 100)])
        #expect(await eventually { model.items.map(\.id) == ["p1", "a", "b"] })
        repository.emit([chat("p1", at: 1), chat("a", at: 900), pinned("b", order: 0, at: 100)])
        #expect(await eventually { model.items.map(\.id) == ["b", "a", "p1"] })
        #expect(model.pinnedCount == 1)
        #expect(await repository.actions.isEmpty)
    }
}

@Suite("Список чатов: прочитано и непрочитано")
@MainActor
struct ChatListUnreadMarkTests {
    @Test("Свайп помечает прочитанный чат непрочитанным и обратно")
    func toggle() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.items.count == 1 })
        await model.toggleRead(chatId: "a")
        #expect(model.items.first?.badge == .dot)
        #expect(await repository.actions == ["unread a"])
        var marked = chat("a", at: 1)
        marked.isMarkedUnread = true
        repository.emit([marked])
        await model.toggleRead(chatId: "a")
        #expect(model.items.first?.badge == nil)
        #expect(await repository.actions == ["unread a", "read-mark a"])
    }

    @Test("Открытие снимает ручную пометку")
    func openClears() async {
        let (model, repository) = makeFeatureList()
        var marked = chat("a", at: 1)
        marked.isMarkedUnread = true
        repository.emit([marked])
        #expect(await eventually { model.items.first?.badge == .dot })
        #expect(model.tabBadge == 1)
        await model.open(chatId: "a")
        #expect(await repository.actions == ["read-mark a"])
        #expect(await repository.marked.isEmpty)
    }

    @Test("Прочитать все в режиме правки")
    func readAll() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("a", at: 3, unread: 2), chat("b", at: 2, unread: 1), chat("c", at: 1)])
        #expect(await eventually { model.items.count == 3 })
        model.isEditing = true
        model.editSelection = ["b"]
        await model.readSelected()
        #expect(await repository.marked == ["b"])
        #expect(!model.isEditing)
        model.isEditing = true
        await model.readSelected()
        #expect(await repository.marked == ["b", "a"])
    }

    @Test("Бейдж вкладки не считает чаты без звука")
    func tabBadge() async {
        let (model, repository) = makeFeatureList()
        var muted = chat("m", at: 1, unread: 40)
        muted.isMuted = true
        repository.emit([chat("a", at: 2, unread: 3), muted])
        #expect(await eventually { model.items.count == 2 })
        #expect(model.tabBadge == 3)
        #expect(model.totalUnread == 43)
        #expect(model.items.last?.badgeMuted == true)
    }
}

@Suite("Список чатов: папки")
@MainActor
struct ChatListFolderTests {
    private func sample() -> [Chat] {
        var bot = chat("bot", at: 5, title: "Помощник", type: .private)
        bot.isBot = true
        var archived = chat("arch", at: 6, unread: 2, title: "Старое")
        archived.isArchived = true
        return [
            chat("p", at: 4, unread: 1, title: "Аня", type: .private),
            chat("g", at: 3, title: "Команда", type: .group),
            chat("ch", at: 2, unread: 5, title: "Новости", type: .channel),
            bot,
            archived,
            chat(Chat.savedMessagesId, at: 1, title: "", type: .private),
        ]
    }

    @Test("Без серверных папок полосы нет, архив отдельной строкой")
    func noFolders() async {
        let (model, repository) = makeFeatureList()
        repository.emit(sample())
        #expect(await eventually { model.items.count == 5 })
        #expect(!model.showsFolders)
        #expect(!model.items.contains { $0.id == "arch" })
        #expect(model.archive == ChatArchiveSummary(count: 1, unreadCount: 1, title: "Старое", preview: "Привет"))
        #expect(model.items.last?.title == "Избранное")
        #expect(model.items.last?.avatar.kind == .savedMessages)
    }

    @Test("Локальные фильтры по типам и счётчики непрочитанных")
    func localFilters() async {
        let (model, repository) = makeFeatureList()
        repository.emit(sample())
        #expect(await eventually { model.items.count == 5 })
        model.usesLocalFilters = true
        #expect(model.showsFolders)
        #expect(model.folders.map(\.title) == ["Все", "Личные", "Группы", "Каналы", "Боты", "Непрочитанные"])
        #expect(model.folders.first { $0.id == "local.unread" }?.unreadCount == 2)
        model.selectFolder("local.private")
        #expect(model.items.map(\.id) == ["p"])
        #expect(model.archive == nil)
        model.selectFolder("local.bots")
        #expect(model.items.map(\.id) == ["bot"])
        model.selectFolder("local.channels")
        #expect(model.items.map(\.id) == ["ch"])
        model.usesLocalFilters = false
        #expect(model.selectedFolderId == ChatFolder.allId)
        #expect(model.items.count == 5)
    }

    @Test("Серверные папки заменяют локальные")
    func serverFolders() async {
        let (model, repository) = makeFeatureList()
        repository.emit(sample())
        #expect(await eventually { model.items.count == 5 })
        repository.emit(folders: [ChatFolder(id: "work", title: "Работа", filter: .chats(["g", "ch"]))])
        #expect(await eventually { model.showsFolders })
        model.usesLocalFilters = true
        #expect(model.folders.map(\.title) == ["Все", "Работа"])
        #expect(model.folders.last?.badge == "1")
        model.selectFolder("work")
        #expect(model.items.map(\.id) == ["g", "ch"])
        repository.emit(folders: [])
        #expect(await eventually { model.selectedFolderId == ChatFolder.allId })
    }

    @Test("Пустая папка отличается от пустого списка")
    func emptyFolder() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("g", at: 1)])
        #expect(await eventually { model.items.count == 1 })
        model.usesLocalFilters = true
        model.selectFolder("local.bots")
        #expect(await eventually { model.content == .empty })
        #expect(model.isFolderEmpty)
    }
}

@Suite("Список чатов: поиск")
@MainActor
struct ChatListSearchTests {
    @Test("Совпадения по заголовку: начало, слово, середина; без регистра и «ё»")
    func localMatch() async {
        let (model, repository) = makeFeatureList()
        repository.emit([
            chat("1", at: 5, title: "Семён Петров"),
            chat("2", at: 4, title: "Команда семьи"),
            chat("3", at: 3, title: "Проект Семь"),
            chat("4", at: 2, title: "Несемейное"),
            chat("5", at: 1, title: "Другое"),
        ])
        #expect(await eventually { model.items.count == 5 })
        model.isSearchActive = true
        model.searchQuery = "сем"
        #expect(model.search.chats.map(\.id) == ["1", "2", "3", "4"])
        model.searchQuery = "СЕМЁН"
        #expect(model.search.chats.map(\.id) == ["1"])
        model.searchQuery = "  "
        #expect(model.search.chats.isEmpty)
    }

    @Test("Недавние: выбор поднимает наверх, удаление и очистка")
    func recents() async {
        let store = FakeRecentSearches(["b"])
        let (model, repository) = makeFeatureList(recents: store)
        repository.emit([chat("a", at: 2, title: "Аня"), chat("b", at: 1, title: "Боря")])
        #expect(await eventually { model.items.count == 2 })
        model.isSearchActive = true
        #expect(await eventually { model.search.recent.map(\.id) == ["b"] })
        await model.selectSearchResult(chatId: "a")
        #expect(model.search.recent.map(\.id) == ["a", "b"])
        #expect(await store.ids == ["a", "b"])
        await model.removeRecent(chatId: "b")
        #expect(model.search.recent.map(\.id) == ["a"])
        await model.clearRecent()
        #expect(model.search.recent.isEmpty)
        #expect(await store.ids.isEmpty)
        model.isSearchActive = false
        #expect(model.searchQuery.isEmpty)
    }

    @Test("Поиск на сервере только при поддержке и без уже известных чатов")
    func serverSearch() async {
        let (model, repository) = makeFeatureList(capabilities: [.serverSearch])
        repository.emit([chat("a", at: 1, title: "Аня")])
        #expect(await eventually { model.items.count == 1 })
        await repository.set(searchResults: [
            ChatSearchResult(id: "a", title: "Аня", type: .private),
            ChatSearchResult(id: "z", title: "Анна Z", subtitle: "@anna", type: .private),
        ])
        model.isSearchActive = true
        model.searchQuery = "ан"
        #expect(await eventually { !model.search.isSearchingServer && model.search.global.count == 1 })
        #expect(model.search.global.first?.id == "z")
        #expect(model.search.chats.map(\.id) == ["a"])
        model.searchQuery = "а"
        #expect(model.search.global.isEmpty)
        #expect(await repository.searches == ["ан"])
    }

    @Test("Без поддержки сервер не спрашивается")
    func noServerSearch() async {
        let (model, repository) = makeFeatureList(capabilities: [])
        repository.emit([chat("a", at: 1, title: "Аня")])
        #expect(await eventually { model.items.count == 1 })
        model.searchQuery = "аня"
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await repository.searches.isEmpty)
        #expect(!model.search.isSearchingServer)
    }
}

@Suite("Список чатов: страницы, набор текста, черновики")
@MainActor
struct ChatListLiveTests {
    @Test("Список растёт страницами, у конца спрашивается сервер")
    func paging() async {
        let (model, repository) = makeFeatureList(capabilities: [.paging])
        let many = (0..<120).map { chat(String(format: "c%03d", $0), at: TimeInterval(1000 - $0)) }
        repository.emit(many)
        #expect(await eventually { model.items.count == ChatListViewModel.pageSize })
        await model.itemAppeared(model.items[10].id)
        #expect(model.items.count == 50)
        await model.itemAppeared(model.items[45].id)
        #expect(model.items.count == 100)
        await model.itemAppeared(model.items[99].id)
        #expect(model.items.count == 120)
        #expect(await repository.pageLoads == 0)
        await model.itemAppeared(model.items[119].id)
        #expect(await repository.pageLoads == 1)
        // Сервер сказал, что страниц больше нет.
        await model.itemAppeared(model.items[119].id)
        #expect(await repository.pageLoads == 1)
    }

    @Test("Набор текста заменяет превью, пока идёт")
    func typing() async {
        let (model, repository) = makeFeatureList()
        repository.emit([chat("p", at: 1, type: .private), chat("g", at: 2, type: .group), chat("ch", at: 3, type: .channel)])
        #expect(await eventually { model.items.count == 3 })
        repository.emit(typing: ["p": ["u1"], "g": ["u1", "u2"], "ch": ["u3"]])
        #expect(await eventually { model.items.first { $0.id == "p" }?.previewStyle == .typing })
        #expect(model.items.first { $0.id == "p" }?.preview == "печатает…")
        #expect(model.items.first { $0.id == "g" }?.preview == "2 участника печатают…")
        #expect(model.items.first { $0.id == "ch" }?.previewStyle == .message)
        repository.emit(typing: [:])
        #expect(await eventually { model.items.first { $0.id == "p" }?.preview == "Привет" })
    }

    @Test("Черновик виден в списке, но не в открытом чате")
    func draft() async {
        let (model, repository) = makeFeatureList()
        var drafted = chat("a", at: 1_790_600_000)
        drafted.draft = ChatDraft(text: "Не забыть\nкупить", updatedAt: Date(timeIntervalSince1970: 1_790_680_000))
        repository.emit([chat("b", at: 1_790_650_000), drafted])
        #expect(await eventually { model.items.count == 2 })
        // Свежий черновик поднимает чат выше.
        #expect(model.items.first?.id == "a")
        #expect(model.items.first?.previewStyle == .draft)
        #expect(model.items.first?.preview == "Не забыть купить")
        #expect(model.items.first?.time == "11:06")
        await model.open(chatId: "a")
        #expect(model.items.first { $0.id == "a" }?.previewStyle == .message)
    }

    @Test("Удаление ждёт подтверждения и доступно только при поддержке")
    func deletion() async {
        let (model, repository) = makeFeatureList(capabilities: [.delete])
        repository.emit([chat("a", at: 1, title: "Аня")])
        #expect(await eventually { model.items.count == 1 })
        model.requestDelete(chatId: "a")
        #expect(model.deletionCandidate?.title == "Аня")
        model.cancelDelete()
        #expect(model.deletionCandidate == nil)
        model.requestDelete(chatId: "a")
        await model.confirmDelete(forEveryone: true)
        #expect(await repository.actions == ["delete a true"])

        let (plain, plainRepository) = makeFeatureList(capabilities: [])
        plainRepository.emit([chat("a", at: 1)])
        #expect(await eventually { plain.items.count == 1 })
        plain.requestDelete(chatId: "a")
        #expect(plain.deletionCandidate == nil)
    }

    @Test("Звук и архив только при поддержке")
    func muteAndArchive() async {
        let (model, repository) = makeFeatureList(capabilities: [.mute, .archive])
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.items.count == 1 })
        await model.toggleMute(chatId: "a")
        await model.toggleArchive(chatId: "a")
        #expect(await repository.actions == ["mute a", "archive a"])
        let (plain, plainRepository) = makeFeatureList(capabilities: [])
        plainRepository.emit([chat("a", at: 1)])
        #expect(await eventually { plain.items.count == 1 })
        await plain.toggleMute(chatId: "a")
        await plain.toggleArchive(chatId: "a")
        #expect(await plainRepository.actions.isEmpty)
    }

    @Test("Заголовок навигации показывает соединение")
    func navigationTitle() async {
        let connection = FakeConnection(initial: .connecting)
        let repository = FakeChatRepository()
        let model = ChatListViewModel(chats: repository, connection: connection)
        model.activate()
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.content == .list && model.connection == .connecting })
        #expect(model.navigationTitle == "Подключение…")
        connection.emit(.offline)
        #expect(await eventually { model.navigationTitle == "Ожидание сети…" })
        connection.emit(.online)
        #expect(await eventually { model.navigationTitle == "Чаты" })
        #expect(model.title(chatId: "a") == "Чат")
        #expect(model.title(chatId: "missing") == "Чат")
    }
}

@Suite("Черновики экрана чата")
@MainActor
struct ChatDraftTests {
    @Test("Черновик восстанавливается, сохраняется после паузы и стирается отправкой")
    func lifecycle() async {
        let drafts = FakeDrafts(["c": "привет"])
        let messages = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: messages, drafts: drafts, draftDelay: .milliseconds(10))
        model.activate()
        #expect(await eventually { model.draft == "привет" })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await drafts.saves == 0)
        model.draft = "привет, как дела"
        #expect(await eventually { await drafts.drafts["c"] == "привет, как дела" })
        await model.send()
        #expect(await eventually { await drafts.drafts["c"] == nil })
    }

    @Test("Уход с экрана сохраняет сразу")
    func flushOnLeave() async {
        let drafts = FakeDrafts()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), drafts: drafts, draftDelay: .seconds(60))
        model.activate()
        model.draft = "текст"
        model.deactivate()
        #expect(await eventually { await drafts.drafts["c"] == "текст" })
    }
}
