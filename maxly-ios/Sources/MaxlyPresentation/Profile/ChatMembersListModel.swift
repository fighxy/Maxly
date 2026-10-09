import Foundation
import Observation
import MaxlyDomain

/// Экран «Участники»: список страницами по 50, значки ролей и поиск. Пока строка поиска
/// пуста — загруженные страницы; с запросом — сразу совпадения среди загруженных (имя или
/// имя для упоминаний, «@» — только оно; фильтр ядра `filterMembers`). Сервер спрашивается, только если загружены не все: через 200 мс после
/// последней правки запроса, одной страницей (test-fixtures/members).
@MainActor
@Observable
public final class ChatMembersListModel: Identifiable {
    public let chatId: String
    public nonisolated var id: String { chatId }
    public let currentUserId: String
    @ObservationIgnored private let actions: any ProfileActionsRepository
    /// Живые статусы «в сети»; `nil` — статусы только из страниц.
    @ObservationIgnored private let presence: (any PresenceProvider)?
    @ObservationIgnored private let formatter: ContactsFormatter
    @ObservationIgnored private let now: () -> Date
    /// Статусы, пришедшие после страниц (`loadPresence`, события ядра), по id.
    private var live: [String: Contact.Presence] = [:]

    public private(set) var members: [ChatMemberEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Есть ещё страницы.
    public private(set) var hasMore = true
    public var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    /// Ответ сервера на текущий запрос; `nil` — ещё не пришёл или поиск не поддерживается.
    public private(set) var serverMatches: [ChatMemberEntry]?
    /// Совпадения среди загруженных от фильтра источника и для какого запроса и списка.
    private var localMatches: (query: String, count: Int, list: [ChatMemberEntry])?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var marker = ChatMembersRules.firstMarker
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Пауза перед запросом поиска, пока печатают.
    @ObservationIgnored var searchDelay: Duration = .milliseconds(200)

    public init(
        chatId: String,
        currentUserId: String,
        actions: any ProfileActionsRepository,
        presence: (any PresenceProvider)? = nil,
        formatter: ContactsFormatter = ContactsFormatter(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.actions = actions
        self.presence = presence
        self.formatter = formatter
        self.now = now
    }

    // MARK: Статус

    /// Статус участника: живой, если известен, иначе из страницы.
    public func presence(of member: ChatMemberEntry) -> Contact.Presence {
        live[member.id] ?? member.presence
    }

    /// Строка под именем на момент `date`; пустая — статус неизвестен. Себе статус не пишется.
    public func status(of member: ChatMemberEntry, at date: Date) -> String {
        guard member.id != currentUserId else { return "" }
        return formatter.status(presence(of: member), now: date)
    }

    public func isOnline(_ member: ChatMemberEntry) -> Bool {
        member.id != currentUserId && presence(of: member) == .online
    }

    /// Следить за статусами, пока список открыт (`.task` вида).
    public func watchPresence() async {
        guard let presence else { return }
        for await ids in presence.changes() {
            await applyPresence(ids, from: presence)
        }
    }

    /// Живые статусы этих участников из общего хранилища.
    func applyPresence(_ ids: Set<String>, from presence: any PresenceProvider) async {
        let known = Set(members.map(\.id))
        for id in ids where known.contains(id) {
            if let value = await presence.presence(of: id), live[id] != value { live[id] = value }
        }
    }

    private func requestPresence(_ page: [ChatMemberEntry]) {
        guard let presence else { return }
        let ids = page.map(\.id).filter { $0 != currentUserId }
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            await presence.refresh(ids)
            // Уже известные статусы не приходят как изменения: читаем их сами.
            await self?.applyPresence(Set(ids), from: presence)
        }
    }

    /// Что показывать: загруженные по порядку ролей или результаты поиска.
    public var visible: [ChatMemberEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ChatMembersRules.ranked(members) }
        // Пока фильтр источника не ответил — то же правило здесь, без пустого кадра.
        let local = if let localMatches, localMatches.query == trimmed, localMatches.count == members.count {
            localMatches.list
        } else {
            ChatMembersRules.filter(members, query: trimmed)
        }
        guard let serverMatches else { return local }
        return ChatMembersRules.append(serverMatches, to: local).list
    }

    /// Первая страница или следующая. Повторный вызов во время загрузки ничего не делает.
    public func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let requested = marker
        do {
            let page = try await actions.membersPage(chatId: chatId, marker: requested)
            let merged = ChatMembersRules.append(page.members, to: members)
            members = merged.list
            requestPresence(page.members)
            errorMessage = nil
            filterLoaded()
            if let next = ChatMembersRules.nextMarker(requested: requested, received: page.marker, newMembers: merged.added) {
                marker = next
            } else {
                hasMore = false
            }
        } catch {
            if error != .cancelled { errorMessage = error.userMessage }
        }
    }

    /// Строка показана: у последней загруженной — следующая страница.
    public func rowAppeared(_ member: ChatMemberEntry) async {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              member.id == ChatMembersRules.ranked(members).last?.id else { return }
        await loadMore()
    }

    /// Диалог с участником. Себя и нечисловые id не открыть.
    public func dialog(with member: ChatMemberEntry) -> DialogDraft? {
        DialogDraft.with(peerId: member.id, me: currentUserId, title: member.name, avatarURL: member.avatarURL)
    }

    private func filterLoaded() {
        filterTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let snapshot = members
        filterTask = Task { [weak self, actions] in
            let found = await actions.filterMembers(snapshot, query: text)
            guard !Task.isCancelled, let self else { return }
            self.localMatches = (text, snapshot.count, found)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        serverMatches = nil
        filterLoaded()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Загружены все — хватает поиска по списку.
        guard !text.isEmpty, hasMore else { return }
        let delay = searchDelay
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.search(text)
        }
    }

    func search(_ text: String) async {
        let found: [ChatMemberEntry]
        do {
            found = try await actions.searchMembers(chatId: chatId, query: text)
        } catch {
            return
        }
        guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
        serverMatches = found
    }
}
