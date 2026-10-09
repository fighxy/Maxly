import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Источник статусов поверх настоящего `PresenceStore`: запоминает, кого спрашивали.
actor FakePresence: PresenceProvider {
    let store = PresenceStore()
    private(set) var refreshed: [[String]] = []

    func refresh(_ userIds: [String]) async {
        refreshed.append(userIds)
    }

    func presence(of userId: String) async -> Contact.Presence? {
        await store.presence(of: userId)
    }

    nonisolated func changes() -> AsyncStream<Set<String>> {
        store.changes()
    }

    /// Записать статус, когда подписчики уже успели подписаться.
    func push(_ presence: Contact.Presence, userId: String) async {
        try? await Task.sleep(for: .milliseconds(20))
        await store.record(presence, userId: userId)
    }
}

@Suite("Статус «в сети»: живые обновления")
@MainActor
struct PresenceLiveTests {
    @Test("Контакты: спрашиваются статусы списка, событие меняет строку")
    func contacts() async {
        let presence = FakePresence()
        let source = FakeContactSource([Contact(id: "2", firstName: "Иван"), Contact(id: "3", firstName: "Анна")], capabilities: [.list, .presence])
        let model = ContactsViewModel(contacts: source, currentUserId: "1", presence: presence)
        model.activate()
        #expect(await eventually { await presence.refreshed.first.map(Set.init) == ["2", "3"] })
        let before = model.sections.flatMap(\.rows).first { $0.id == "3" }
        #expect(before?.isOnline == false)
        #expect(before?.status == "")
        await presence.push(.online, userId: "3")
        #expect(await eventually { model.sections.flatMap(\.rows).first { $0.id == "3" }?.isOnline == true })
        #expect(model.sections.flatMap(\.rows).first { $0.id == "3" }?.status == "В сети")
        model.deactivate()
    }

    @Test("Участники: статусы страницы спрашиваются без себя, строка из живого статуса")
    func members() async {
        let presence = FakePresence()
        let page = ChatMembersPage(members: [
            ChatMemberEntry(id: "1", name: "Я"),
            ChatMemberEntry(id: "2", name: "Аня", presence: .longAgo),
        ], marker: nil)
        let model = ChatMembersListModel(chatId: "-5", currentUserId: "1", actions: OnePage(page: page), presence: presence)
        await model.loadMore()
        #expect(await eventually { await presence.refreshed == [["2"]] })
        let anna = model.members.first { $0.id == "2" }!
        let me = model.members.first { $0.id == "1" }!
        #expect(model.status(of: anna, at: Date()) == "Был(а) давно")
        #expect(model.status(of: me, at: Date()) == "")
        let watch = Task { await model.watchPresence() }
        await presence.push(.online, userId: "2")
        #expect(await eventually { model.isOnline(anna) })
        #expect(model.status(of: anna, at: Date()) == "В сети")
        watch.cancel()
    }

    @Test("Уже известный статус берётся сразу, без события об изменении")
    func knownBeforeLoad() async {
        let presence = FakePresence()
        await presence.store.record(.online, userId: "2")
        let page = ChatMembersPage(members: [ChatMemberEntry(id: "2", name: "Аня")], marker: nil)
        let model = ChatMembersListModel(chatId: "-5", currentUserId: "1", actions: OnePage(page: page), presence: presence)
        await model.loadMore()
        #expect(await eventually { model.members.first.map(model.isOnline) == true })
    }
}

/// Одна страница участников.
private struct OnePage: ProfileActionsRepository {
    let page: ChatMembersPage
    func members(chatId: String) async throws(MaxlyError) -> [ProfileMember] { [] }
    func commonChats(userId: String) async throws(MaxlyError) -> [CommonChat] { [] }
    func complaintReasons(for target: ComplaintTarget) async throws(MaxlyError) -> [ComplaintReason] { [] }
    func complain(about target: ComplaintTarget, reasonId: Int) async throws(MaxlyError) -> Bool { false }
    func isBlocked(userId: String) async throws(MaxlyError) -> Bool { false }
    func setBlocked(userId: String, blocked: Bool) async throws(MaxlyError) {}
    func membersPage(chatId: String, marker: Int64) async throws(MaxlyError) -> ChatMembersPage { page }
}
