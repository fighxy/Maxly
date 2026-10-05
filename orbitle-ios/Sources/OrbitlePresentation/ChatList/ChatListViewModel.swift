import Foundation
import Observation
import OrbitleDomain

/// Строка «Архив чатов» над списком.
public struct ChatArchiveSummary: Equatable, Sendable {
    public var count: Int
    public var unreadCount: Int
    /// Заголовок свежего чата архива (вторая строка).
    public var title: String
    /// Его превью (третья строка).
    public var preview: String
}

/// Папка в полосе над списком с числом непрочитанных чатов.
public struct ChatFolderTab: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let unreadCount: Int
    /// `nil` без непрочитанных.
    public var badge: String? { unreadCount > 0 ? ChatListFormatter.compactCount(unreadCount) : nil }
}

/// Список чатов: живой поток из репозитория, папки, поиск, закреплённые, действия
/// строк, режим правки и индикатор соединения. Экран только рисует готовые значения.
@MainActor
@Observable
public final class ChatListViewModel {
    /// Что показать вместо списка, когда строк нет.
    public enum Content: Equatable, Sendable {
        case loading
        case list
        case empty
        case offline
        case failed(String)
    }

    /// Сколько строк показывать сразу; дальше список растёт страницами при прокрутке.
    public static let pageSize = 50
    /// Сколько чатов можно закрепить. Сервер может отказать и раньше, тогда покажется его ошибка.
    public static let defaultPinLimit = 10

    /// Все чаты в порядке списка: закреплённые, затем по свежести.
    public private(set) var chats: [Chat] = []
    /// Строки выбранной папки без архива, в пределах показанных страниц.
    public private(set) var items: [ChatListItem] = [] {
        didSet {
            let ids = items.map(\.id)
            let oldIds = oldValue.map(\.id)
            itemsChange = CollectionChange.between(oldIds, ids)
            if ids != oldIds { itemsVersion &+= 1 }
        }
    }
    /// Как список изменился последним обновлением: смена папки и новая страница — без анимации.
    public private(set) var itemsChange: CollectionChange = .none
    /// Растёт, когда меняются состав или порядок строк: экран анимирует по нему, не сравнивая
    /// списки id при каждой перерисовке.
    public private(set) var itemsVersion = 0

    /// Аватары и миниатюры первых строк — их качают заранее, пока список докручивается.
    public func prefetchImageURLs(limit: Int = 40) -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        for item in items.prefix(limit) {
            var candidates: [URL] = []
            if case .photo(let url, _) = item.avatar.kind { candidates.append(url) }
            if let thumbnail = item.thumbnailURL { candidates.append(thumbnail) }
            for url in candidates where !url.isFileURL && seen.insert(url).inserted { urls.append(url) }
        }
        return urls
    }
    public private(set) var archive: ChatArchiveSummary?
    public private(set) var folders: [ChatFolderTab] = []
    public private(set) var selectedFolderId = ChatFolder.allId
    public private(set) var isRefreshing = false
    public private(set) var isLoadingMore = false
    public private(set) var error: OrbitleError?
    public private(set) var connection: ConnectionState
    /// Чат, открытый сейчас на экране. Его новые сообщения сразу отмечаются прочитанными.
    public private(set) var openChatId: String?
    /// Идёт догрузка после восстановления соединения: плашка говорит «Обновление…».
    public private(set) var isCatchingUp = false
    /// Кто печатает: id чата → id пользователей.
    public private(set) var typing: [String: [String]] = [:]

    // Поиск
    public private(set) var search = ChatSearchState()
    public var isSearchActive = false {
        didSet {
            guard isSearchActive != oldValue else { return }
            if !isSearchActive { searchQuery = "" }
            rebuildSearch()
        }
    }
    public var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            rebuildSearch()
            scheduleServerSearch()
        }
    }

    // Режим правки
    public var isEditing = false {
        didSet { if !isEditing { editSelection.removeAll() } }
    }
    public var editSelection: Set<String> = []
    /// Чат, удаление которого ждёт подтверждения.
    public private(set) var deletionCandidate: ChatListItem?
    /// Чат, очистка переписки которого ждёт подтверждения.
    public private(set) var clearCandidate: ChatListItem?

    /// Локальные папки по типам, когда серверных нет. Выключены: полоса папок видна,
    /// только если у пользователя есть папки.
    public var usesLocalFilters = false {
        didSet {
            guard usesLocalFilters != oldValue else { return }
            rebuildFolders()
            rebuildItems()
        }
    }

    /// Последний снимок репозитория без ожидающих правок экрана.
    private var snapshot: [Chat] = []
    /// Первое значение из репозитория уже пришло.
    private var hasSnapshot = false
    /// Хотя бы одно обновление с сервера закончилось (успешно или нет).
    private var hasRefreshed = false
    private var visibleLimit = ChatListViewModel.pageSize
    private var hasMorePages = true
    private var serverFolders: [ChatFolder] = []
    private var recentIds: [String] = []
    /// Закрепление, отправленное в репозиторий, но ещё не пришедшее в снимке: без него
    /// строка на миг вернулась бы на старое место.
    private var pendingPins: [String: Int?] = [:]
    /// Порядок закреплённых после перетаскивания, пока снимок его не подтвердил.
    private var pendingPinSequence: [String]?
    private var pendingUnreadMarks: [String: Bool] = [:]

    @ObservationIgnored private let repository: any ChatRepository
    @ObservationIgnored private let status: (any ConnectionStatusProvider)?
    @ObservationIgnored private let recents: (any RecentSearchStore)?
    @ObservationIgnored private let formatter: ChatListFormatter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let pinLimit: Int
    @ObservationIgnored private let searchDelay: Duration
    @ObservationIgnored private var watches: [Task<Void, Never>] = []
    @ObservationIgnored private var marking: Set<String> = []
    @ObservationIgnored private var catchUpTask: Task<Void, Never>?
    @ObservationIgnored private var serverSearchTask: Task<Void, Never>?
    @ObservationIgnored private var foundMessages: [FoundMessage] = []

    public init(
        chats: any ChatRepository,
        connection: (any ConnectionStatusProvider)? = nil,
        recentSearches: (any RecentSearchStore)? = nil,
        formatter: ChatListFormatter = ChatListFormatter(),
        pinLimit: Int = ChatListViewModel.defaultPinLimit,
        searchDelay: Duration = .milliseconds(300),
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = chats
        self.status = connection
        self.recents = recentSearches
        self.formatter = formatter
        self.pinLimit = pinLimit
        self.searchDelay = searchDelay
        self.now = now
        self.connection = connection == nil ? .online : .connecting
        rebuildFolders()
    }

    // MARK: Состояние для экрана

    public var capabilities: ChatListCapabilities { repository.capabilities }

    public var content: Content {
        if !items.isEmpty || archive != nil { return .list }
        if !hasSnapshot || (isRefreshing && !hasRefreshed) { return .loading }
        if connection == .offline { return .offline }
        if let message = error?.userMessage { return .failed(message) }
        if !hasRefreshed, connection == .connecting { return .loading }
        return .empty
    }

    /// В выбранной папке нет чатов, хотя в списке они есть.
    public var isFolderEmpty: Bool {
        content == .empty && selectedFolderId != ChatFolder.allId && !chats.isEmpty
    }

    /// Плашка над списком. Когда список пуст из-за сети, об этом уже говорит `content`.
    public var banner: String? {
        guard content != .offline else { return nil }
        switch connection {
        case .online: return isCatchingUp && content == .list ? "Обновление…" : nil
        case .connecting: return "Подключение…"
        case .offline: return "Нет соединения. Показаны сохранённые чаты"
        }
    }

    /// Заголовок навигации: вместо «Чаты» — состояние соединения, пока его нет.
    public var navigationTitle: String {
        guard content != .offline else { return "Чаты" }
        switch connection {
        case .online: return isCatchingUp ? "Обновление…" : "Чаты"
        case .connecting: return "Подключение…"
        case .offline: return "Ожидание сети…"
        }
    }

    /// Ошибка поверх непустого списка. Сетевую ошибку уже показывает плашка.
    public var inlineError: String? {
        guard content == .list, let error else { return nil }
        if error == .networkUnavailable, connection != .online { return nil }
        return error.userMessage
    }

    public var totalUnread: Int {
        chats.reduce(0) { $0 + max($1.unreadCount, 0) }
    }

    /// Число на вкладке «Чаты»: непрочитанные без чатов без звука и архива.
    public var tabBadge: Int {
        chats.reduce(0) { sum, chat in
            guard !chat.isMuted, !chat.isArchived else { return sum }
            return sum + (chat.unreadCount > 0 ? chat.unreadCount : (chat.isMarkedUnread ? 1 : 0))
        }
    }

    /// Полоса папок видна, когда кроме «Все» есть хотя бы одна папка.
    public var showsFolders: Bool { folders.count > 1 }

    public var pinnedCount: Int { chats.filter { $0.isPinned && !$0.isArchived }.count }

    /// Закреплённые можно перетаскивать: в папке «Все», в режиме правки и если источник умеет.
    public var canReorderPinned: Bool {
        isEditing && selectedFolderId == ChatFolder.allId && capabilities.contains(.reorderPins) && pinnedCount > 1
    }

    /// Строки архива, для экрана «Архив чатов».
    public var archivedItems: [ChatListItem] {
        let date = now()
        return chats.filter(\.isArchived).map { item($0, at: date) }
    }

    public func title(chatId: String) -> String {
        chats.first { $0.id == chatId }.map(formatter.title(for:)) ?? "Чат"
    }

    /// Куда можно переслать сообщение: все чаты вне архива в порядке списка, кроме `excluding`.
    public func forwardTargets(excluding chatId: String? = nil) -> [ChatListItem] {
        let now = Date()
        return chats
            .filter { !$0.isArchived && $0.id != chatId }
            .map { formatter.item(for: $0, now: now, showDraft: false) }
    }

    public func chat(id: String) -> Chat? {
        chats.first { $0.id == id }
    }

    // MARK: Жизненный цикл

    /// Подписка на чаты, папки, набор текста и соединение. Повторный вызов ничего не делает.
    public func activate() {
        guard watches.isEmpty else { return }
        let stream = repository.chats()
        watches.append(Task { [weak self] in
            for await chats in stream {
                guard let self else { return }
                self.apply(chats)
            }
        })
        let folderStream = repository.folders()
        watches.append(Task { [weak self] in
            for await folders in folderStream {
                guard let self else { return }
                self.serverFolders = folders.filter { $0.id != ChatFolder.allId }
                self.rebuildFolders()
                self.rebuildItems()
            }
        })
        let typingStream = repository.typing()
        watches.append(Task { [weak self] in
            for await typing in typingStream {
                guard let self else { return }
                guard self.typing != typing else { continue }
                self.typing = typing
                self.rebuildItems()
            }
        })
        if let recents {
            watches.append(Task { [weak self] in
                let ids = await recents.recent()
                guard let self else { return }
                self.recentIds = ids
                self.rebuildSearch()
            })
        }
        if let status {
            let states = status.connectionStates()
            watches.append(Task { [weak self] in
                for await state in states {
                    guard let self else { return }
                    let previous = self.connection
                    self.connection = state
                    if state == .online, previous != .online, self.hasRefreshed {
                        // Связь вернулась после обрыва: список мог устареть, догружаем сразу.
                        // Отдельной задачей, чтобы долгий запрос не задерживал следующие
                        // состояния соединения.
                        self.startCatchUp()
                    }
                }
            })
        }
    }

    public func deactivate() {
        watches.forEach { $0.cancel() }
        watches.removeAll()
        catchUpTask?.cancel()
        catchUpTask = nil
        serverSearchTask?.cancel()
        serverSearchTask = nil
    }

    // MARK: Обновление и страницы

    /// Обновление с сервера (потянуть вниз, вход на экран, кнопка «Повторить»).
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasRefreshed = true
        }
        do {
            try await repository.refresh()
            error = nil
            hasMorePages = true
        } catch {
            if error != .cancelled { self.error = error }
        }
        // Метки времени зависят от текущего дня: пересчитываем после обновления.
        rebuildItems()
    }

    /// Строка `id` появилась на экране. У конца списка показывается следующая страница,
    /// а когда локальные кончились — догружается страница с сервера, если источник умеет.
    public func itemAppeared(_ id: String) async {
        guard let index = items.firstIndex(where: { $0.id == id }), index >= items.count - 10 else { return }
        let total = filteredChats().count
        if items.count < total {
            visibleLimit += Self.pageSize
            rebuildItems()
            return
        }
        guard capabilities.contains(.paging), hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            hasMorePages = try await repository.loadMoreChats()
            visibleLimit += Self.pageSize
            rebuildItems()
        } catch {
            if error != .cancelled, error != .networkUnavailable { self.error = error }
        }
    }

    // MARK: Папки

    public func selectFolder(_ id: String) {
        guard id != selectedFolderId, folders.contains(where: { $0.id == id }) else { return }
        selectedFolderId = id
        visibleLimit = Self.pageSize
        isEditing = false
        rebuildItems()
        itemsChange = .reload
    }

    // MARK: Открытие и прочтение

    /// Чат открыт на экране (`nil`, если закрыт). Непрочитанные сбрасываются сразу.
    public func open(chatId: String?) async {
        let previous = openChatId
        openChatId = chatId
        if previous != chatId { rebuildItems() }
        guard let chatId else { return }
        if let chat = chats.first(where: { $0.id == chatId }) {
            if chat.isMarkedUnread { await setMarkedUnread(false, chatId: chatId) }
            if chat.unreadCount == 0 { return }
        }
        await markRead(chatId)
    }

    /// Пометка «непрочитано» с сообщения: чат снова непрочитан на сервере начиная с `date`.
    /// Открытый чат перестаёт считаться открытым до запроса, иначе ответ тут же отметил бы его
    /// прочитанным. `true` — сервер принял пометку, экран чата можно закрывать; при ошибке чат
    /// снова считается открытым.
    public func markUnread(chatId: String, from date: Date) async -> Bool {
        let wasOpen = openChatId == chatId
        if wasOpen {
            openChatId = nil
            rebuildItems()
        }
        do {
            try await repository.markUnread(chatId: chatId, from: date)
            return true
        } catch {
            if wasOpen, openChatId == nil {
                openChatId = chatId
                rebuildItems()
            }
            show(error)
            return false
        }
    }

    /// Свайп «Прочитано / Непрочитано».
    public func toggleRead(chatId: String) async {
        guard let chat = chats.first(where: { $0.id == chatId }) else { return }
        if chat.isUnread {
            if chat.isMarkedUnread { await setMarkedUnread(false, chatId: chatId) }
            if chat.unreadCount > 0 { await markRead(chatId) }
        } else if capabilities.contains(.markUnread) {
            await setMarkedUnread(true, chatId: chatId)
        }
    }

    /// Прочитать выбранные в режиме правки или, если ничего не выбрано, все чаты папки.
    public func readSelected() async {
        let ids = editSelection.isEmpty ? filteredChats().filter(\.isUnread).map(\.id) : Array(editSelection)
        for id in ids {
            guard let chat = chats.first(where: { $0.id == id }), chat.isUnread else { continue }
            if chat.isMarkedUnread { await setMarkedUnread(false, chatId: id) }
            if chat.unreadCount > 0 { await markRead(id) }
        }
        isEditing = false
    }

    // MARK: Закреплённые

    /// Закрепить или открепить. Новый закреплённый встаёт первым; при лимите показывается ошибка.
    public func togglePin(chatId: String) async {
        guard capabilities.contains(.pin), let chat = chats.first(where: { $0.id == chatId }) else { return }
        let pin = !chat.isPinned
        if pin, pinnedCount >= pinLimit {
            error = .rejected("Можно закрепить не больше \(pinLimit) чатов. Открепите один из них")
            return
        }
        let order: Int? = pin ? (chats.compactMap(\.pinOrder).min() ?? 1) - 1 : nil
        pendingPins[chatId] = .some(order)
        reorder()
        do {
            try await repository.setPinned(pin, chatId: chatId)
        } catch {
            pendingPins[chatId] = nil
            reorder()
            show(error)
        }
    }

    /// Перетаскивание закреплённых в режиме правки. Индексы — среди закреплённых строк.
    public func movePinned(from source: IndexSet, to destination: Int) async {
        guard canReorderPinned else { return }
        var pinned = chats.filter { $0.isPinned && !$0.isArchived }.map(\.id)
        let moving = source.sorted().filter { $0 < pinned.count }.map { pinned[$0] }
        guard !moving.isEmpty else { return }
        let insertAt = destination - source.filter { $0 < destination }.count
        pinned.removeAll { moving.contains($0) }
        pinned.insert(contentsOf: moving, at: min(max(insertAt, 0), pinned.count))
        let previous = pendingPins
        for (index, id) in pinned.enumerated() { pendingPins[id] = .some(index) }
        pendingPinSequence = pinned
        reorder()
        do {
            try await repository.reorderPinned(pinned)
        } catch {
            pendingPins = previous
            pendingPinSequence = nil
            reorder()
            show(error)
        }
    }

    // MARK: Уведомления, архив, удаление

    public func toggleMute(chatId: String) async {
        guard capabilities.contains(.mute), let chat = chats.first(where: { $0.id == chatId }) else { return }
        do {
            try await repository.setMuted(!chat.isMuted, chatId: chatId)
        } catch {
            show(error)
        }
    }

    public func toggleArchive(chatId: String) async {
        guard capabilities.contains(.archive), let chat = chats.first(where: { $0.id == chatId }) else { return }
        do {
            try await repository.setArchived(!chat.isArchived, chatId: chatId)
        } catch {
            show(error)
        }
    }

    /// Первый шаг удаления: экран спрашивает подтверждение.
    public func requestDelete(chatId: String) {
        guard capabilities.contains(.delete) else { return }
        deletionCandidate = items.first { $0.id == chatId }
            ?? chats.first { $0.id == chatId }.map { formatter.item(for: $0, now: now()) }
    }

    public func cancelDelete() {
        deletionCandidate = nil
    }

    /// Удалить чат на сервере: `forEveryone` — у всех, иначе только у себя.
    public func confirmDelete(forEveryone: Bool) async {
        guard let candidate = deletionCandidate else { return }
        deletionCandidate = nil
        do {
            try await repository.delete(chatId: candidate.id, forEveryone: forEveryone)
        } catch {
            show(error)
        }
    }

    public func requestClear(chatId: String) {
        guard capabilities.contains(.delete) else { return }
        clearCandidate = items.first { $0.id == chatId }
            ?? chats.first { $0.id == chatId }.map { formatter.item(for: $0, now: now()) }
    }

    public func cancelClear() {
        clearCandidate = nil
    }

    /// Очистка из профиля: кандидат диалога не нужен.
    public func confirmClear(chatId: String, forEveryone: Bool) async {
        guard capabilities.contains(.delete) else { return }
        do {
            try await repository.clearHistory(chatId: chatId, forEveryone: forEveryone)
        } catch {
            show(error)
        }
    }

    /// Удаление из профиля. `true` — сервер принял, экран чата можно закрыть.
    public func deleteNow(chatId: String, forEveryone: Bool) async -> Bool {
        guard capabilities.contains(.delete) else { return false }
        do {
            try await repository.delete(chatId: chatId, forEveryone: forEveryone)
            return true
        } catch {
            show(error)
            return false
        }
    }

    /// Выйти из группы или отписаться от канала. `true` — сервер принял, экран чата можно закрыть.
    public func leave(chatId: String) async -> Bool {
        do {
            try await repository.leave(chatId: chatId)
            return true
        } catch {
            show(error)
            return false
        }
    }

    public func confirmClear(forEveryone: Bool) async {
        guard let candidate = clearCandidate else { return }
        clearCandidate = nil
        do {
            try await repository.clearHistory(chatId: candidate.id, forEveryone: forEveryone)
        } catch {
            show(error)
        }
    }

    // MARK: Поиск

    /// Пользователь выбрал чат из поиска: он становится первым в недавних.
    public func selectSearchResult(chatId: String) async {
        recentIds.removeAll { $0 == chatId }
        recentIds.insert(chatId, at: 0)
        rebuildSearch()
        await recents?.add(chatId: chatId)
    }

    public func removeRecent(chatId: String) async {
        recentIds.removeAll { $0 == chatId }
        rebuildSearch()
        await recents?.remove(chatId: chatId)
    }

    public func clearRecent() async {
        recentIds.removeAll()
        rebuildSearch()
        await recents?.clear()
    }

    public func dismissError() {
        error = nil
    }

    // MARK: Внутреннее

    func apply(_ next: [Chat]) {
        // Подтверждённое снимком закрепление больше не нужно держать поверх.
        if let sequence = pendingPinSequence {
            let pinned = next.filter { $0.isPinned && !$0.isArchived }.sorted(by: Chat.listOrder).map(\.id)
            if pinned == sequence {
                sequence.forEach { pendingPins[$0] = nil }
                pendingPinSequence = nil
            }
        }
        for (id, order) in pendingPins where !(pendingPinSequence?.contains(id) ?? false) {
            guard let chat = next.first(where: { $0.id == id }) else {
                pendingPins[id] = nil
                continue
            }
            if (chat.pinOrder == nil) == (order == nil) { pendingPins[id] = nil }
        }
        for (id, marked) in pendingUnreadMarks {
            if let chat = next.first(where: { $0.id == id }), chat.isMarkedUnread == marked { pendingUnreadMarks[id] = nil }
        }
        snapshot = next
        hasSnapshot = true
        reorder()
        if let open = openChatId,
           let chat = chats.first(where: { $0.id == open }),
           chat.unreadCount > 0,
           !marking.contains(open) {
            // Новое сообщение пришло в открытый чат: он уже на экране, значит прочитан.
            Task { [weak self] in await self?.markRead(open) }
        }
    }

    /// Накладывает ожидающие правки и сортирует.
    private func reorder() {
        var sorted = snapshot
        for index in sorted.indices {
            let id = sorted[index].id
            if let order = pendingPins[id] { sorted[index].pinOrder = order }
            if let marked = pendingUnreadMarks[id] { sorted[index].isMarkedUnread = marked }
        }
        chats = sorted.sorted(by: Chat.listOrder)
        rebuildItems()
    }

    private func folderDefinitions() -> [ChatFolder] {
        let extra = serverFolders.isEmpty && usesLocalFilters ? ChatFolder.localFilters : serverFolders
        return [ChatFolder.all] + extra
    }

    private func rebuildFolders() {
        let definitions = folderDefinitions()
        folders = definitions.map { folder in
            ChatFolderTab(
                id: folder.id,
                title: folder.title,
                unreadCount: chats.filter { folder.contains($0) && $0.isUnread && !$0.isMuted }.count
            )
        }
        if !folders.contains(where: { $0.id == selectedFolderId }) {
            selectedFolderId = ChatFolder.allId
        }
    }

    private func filteredChats() -> [Chat] {
        let folder = folderDefinitions().first { $0.id == selectedFolderId } ?? .all
        return chats.filter { folder.contains($0) }
    }

    private func item(_ chat: Chat, at date: Date) -> ChatListItem {
        formatter.item(for: chat, now: date, typing: typing[chat.id] ?? [], showDraft: chat.id != openChatId)
    }

    private func rebuildItems() {
        let date = now()
        let visible = filteredChats().prefix(visibleLimit)
        let next = visible.map { item($0, at: date) }
        if next != items { items = next }
        let archived = chats.filter(\.isArchived)
        let nextArchive: ChatArchiveSummary? = archived.first.map { latest in
            ChatArchiveSummary(
                count: archived.count,
                unreadCount: archived.filter { $0.isUnread && !$0.isMuted }.count,
                title: formatter.title(for: latest),
                preview: formatter.preview(for: latest)
            )
        }
        if selectedFolderId == ChatFolder.allId ? nextArchive != archive : archive != nil {
            archive = selectedFolderId == ChatFolder.allId ? nextArchive : nil
        }
        rebuildFolders()
        rebuildSearch()
    }

    private func rebuildSearch() {
        var next = ChatSearchState()
        next.global = search.global
        next.isSearchingServer = search.isSearchingServer
        let date = now()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            next.global = []
            next.isSearchingServer = false
            foundMessages = []
            if isSearchActive {
                next.recent = recentIds.compactMap { id in chats.first { $0.id == id } }.map { item($0, at: date) }
            }
        } else {
            let found = ChatListSearch.match(chats, query: query, title: formatter.title(for:))
            next.chats = found.map { item($0, at: date) }
            let known = Set(chats.map(\.id))
            next.global = next.global.filter { !known.contains($0.id) }
            next.messages = messageRows(at: date)
        }
        if next != search { search = next }
    }

    /// Строки найденных сообщений с названием чата из списка.
    private func messageRows(at date: Date) -> [ChatSearchMessage] {
        guard !foundMessages.isEmpty else { return [] }
        let byId = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return foundMessages.map { found in
            ChatSearchMessage(
                chatId: found.chatId,
                messageId: found.messageId,
                chatTitle: byId[found.chatId].map(formatter.title(for:)) ?? ChatSearchMessage.unknownChatTitle,
                snippet: ChatSearchMessage.snippet(found.text),
                time: found.date.map { formatter.timeLabel(for: $0, now: date) } ?? ""
            )
        }
    }

    private func scheduleServerSearch() {
        serverSearchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard capabilities.contains(.serverSearch), query.count >= 2 else {
            foundMessages = []
            if search.isSearchingServer || !search.global.isEmpty || !search.messages.isEmpty {
                search.isSearchingServer = false
                search.global = []
                search.messages = []
            }
            return
        }
        search.isSearchingServer = true
        let delay = searchDelay
        serverSearchTask = Task { [weak self, repository] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Чаты и сообщения ищутся вместе; ошибка одного не прячет другое.
            async let publicChats: [ChatSearchResult] = (try? await repository.search(query: query)) ?? []
            async let messages: [FoundMessage] = (try? await repository.searchMessages(query: query)) ?? []
            let (results, found) = await (publicChats, messages)
            guard !Task.isCancelled, let self, self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            let known = Set(self.chats.map(\.id))
            self.foundMessages = found
            self.search.global = results.filter { !known.contains($0.id) }
            self.search.messages = self.messageRows(at: self.now())
            self.search.isSearchingServer = false
        }
    }

    private func setMarkedUnread(_ marked: Bool, chatId: String) async {
        pendingUnreadMarks[chatId] = marked
        reorder()
        do {
            try await repository.setMarkedUnread(marked, chatId: chatId)
        } catch {
            pendingUnreadMarks[chatId] = nil
            reorder()
            // Без поддержки источника снять пометку нечем, это не ошибка пользователя.
            if error != .invalidRequest { show(error) }
        }
    }

    private func startCatchUp() {
        catchUpTask?.cancel()
        catchUpTask = Task { [weak self] in await self?.catchUp() }
    }

    private func catchUp() async {
        isCatchingUp = true
        defer { isCatchingUp = false }
        await refresh()
    }

    private func show(_ failure: OrbitleError) {
        if failure != .cancelled { error = failure }
    }

    private func markRead(_ chatId: String) async {
        guard !marking.contains(chatId) else { return }
        marking.insert(chatId)
        defer { marking.remove(chatId) }
        // Бейдж пропадает сразу, не дожидаясь ответа базы.
        if let index = snapshot.firstIndex(where: { $0.id == chatId }), snapshot[index].unreadCount > 0 {
            snapshot[index].unreadCount = 0
            reorder()
        }
        do {
            try await repository.markAsRead(chatId: chatId)
        } catch {
            // Без сети отметка догонит сервер при следующем открытии, экран её не показывает.
            if error != .cancelled, error != .networkUnavailable {
                self.error = error
            }
        }
    }
}
