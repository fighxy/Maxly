import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Участники страницами: маркер — номер следующей страницы, после последней его нет.
private actor PagedMembers: ProfileActionsRepository {
    private let pages: [Int64: ChatMembersPage]
    private let found: [ChatMemberEntry]?
    private(set) var requested: [Int64] = []
    private(set) var searches: [String] = []

    init(pages: [Int64: ChatMembersPage], found: [ChatMemberEntry]? = nil) {
        self.pages = pages
        self.found = found
    }

    func members(chatId: String) async throws(OrbitleError) -> [ProfileMember] { [] }
    func commonChats(userId: String) async throws(OrbitleError) -> [CommonChat] { [] }
    func complaintReasons(for target: ComplaintTarget) async throws(OrbitleError) -> [ComplaintReason] { [] }
    func complain(about target: ComplaintTarget, reasonId: Int) async throws(OrbitleError) -> Bool { false }
    func isBlocked(userId: String) async throws(OrbitleError) -> Bool { false }
    func setBlocked(userId: String, blocked: Bool) async throws(OrbitleError) {}

    func membersPage(chatId: String, marker: Int64) async throws(OrbitleError) -> ChatMembersPage {
        requested.append(marker)
        guard let page = pages[marker] else { throw .networkUnavailable }
        return page
    }

    func searchMembers(chatId: String, query: String) async throws(OrbitleError) -> [ChatMemberEntry] {
        searches.append(query)
        guard let found else { throw .invalidRequest }
        return found
    }
}

@MainActor
@Suite("Участники: страницы, роли, поиск")
struct ChatMembersListModelTests {
    func member(_ id: String, _ name: String, role: ChatMemberRole = .member, alias: String? = nil) -> ChatMemberEntry {
        ChatMemberEntry(id: id, name: name, role: role, alias: alias)
    }

    @Test("Страницы идут по маркеру до конца, повторы выбрасываются, владелец и админы сверху")
    func paging() async {
        let repo = PagedMembers(pages: [
            0: ChatMembersPage(members: [member("1", "Аня"), member("2", "Борис", role: .admin, alias: "модератор")], marker: 2),
            2: ChatMembersPage(members: [member("2", "Борис"), member("3", "Вера", role: .owner)], marker: nil),
        ])
        let model = ChatMembersListModel(chatId: "-5", currentUserId: "1", actions: repo)
        await model.loadMore()
        #expect(model.hasMore)
        await model.rowAppeared(model.visible.last!)
        #expect(!model.hasMore)
        #expect(await repo.requested == [0, 2])
        #expect(model.visible.map(\.id) == ["3", "2", "1"])
        #expect(model.visible.map(\.badge) == ["владелец", "модератор", nil])
        await model.loadMore()
        #expect(await repo.requested == [0, 2])
    }

    @Test("Поиск: сразу среди загруженных (ё = е), затем ответ сервера без повторов")
    func search() async {
        let repo = PagedMembers(
            pages: [0: ChatMembersPage(members: [member("1", "Пётр"), member("2", "Анна")], marker: nil)],
            found: [member("1", "Пётр"), member("9", "Петров")]
        )
        let model = ChatMembersListModel(chatId: "-5", currentUserId: "1", actions: repo)
        model.searchDelay = .zero
        await model.loadMore()
        model.query = " петр"
        #expect(model.visible.map(\.id) == ["1"])
        await model.search("петр")
        #expect(model.visible.map(\.id) == ["1", "9"])
        model.query = ""
        #expect(model.visible.map(\.id) == ["1", "2"])
    }

    @Test("Касание открывает диалог; себя не открыть")
    func dialog() {
        let model = ChatMembersListModel(chatId: "-5", currentUserId: "1", actions: PagedMembers(pages: [:]))
        #expect(model.dialog(with: member("1", "Я")) == nil)
        let draft = model.dialog(with: member("6", "Аня"))
        #expect(draft?.peerId == "6")
        #expect(draft?.chatId == String(Int64(1) ^ Int64(6)))
    }

    @Test("Ошибка страницы показывается, повтор спрашивает ту же страницу")
    func failure() async {
        let repo = PagedMembers(pages: [:])
        let model = ChatMembersListModel(chatId: "-5", currentUserId: "1", actions: repo)
        await model.loadMore()
        #expect(model.errorMessage != nil)
        #expect(model.hasMore)
        await model.loadMore()
        #expect(await repo.requested == [0, 0])
    }
}
