import Foundation
import Observation
import OrbitleDomain

/// Экран «Участники»: список страницами по 50, значки ролей и поиск. Пока строка поиска
/// пуста — загруженные страницы; с запросом — сразу совпадения среди загруженных, затем ответ
/// сервера (если источник умеет искать).
@MainActor
@Observable
public final class ChatMembersListModel: Identifiable {
    public let chatId: String
    public nonisolated var id: String { chatId }
    public let currentUserId: String
    @ObservationIgnored private let actions: any ProfileActionsRepository

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
    @ObservationIgnored private var marker = ChatMembersRules.firstMarker
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Пауза перед запросом поиска, пока печатают.
    @ObservationIgnored var searchDelay: Duration = .milliseconds(350)

    public init(chatId: String, currentUserId: String, actions: any ProfileActionsRepository) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.actions = actions
    }

    /// Что показывать: загруженные по порядку ролей или результаты поиска.
    public var visible: [ChatMemberEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ChatMembersRules.ranked(members) }
        let local = ChatMembersRules.filter(members, query: trimmed)
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
            errorMessage = nil
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

    private func scheduleSearch() {
        searchTask?.cancel()
        serverMatches = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
