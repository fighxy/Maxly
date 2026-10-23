import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private actor SetupAdmin: ChatAdminRepository {
    var link = "https://max.ru/join/abc"
    private(set) var added: [[String]] = []

    func snapshot(chatId: String) async throws(MaxlyError) -> ChatAdminSnapshot {
        ChatAdminSnapshot(title: "Новости", description: "", link: link, ownerId: "1", commentsEnabled: nil, onlyOwnerRenames: false, allCanPin: false, onlyAdminAdds: false, onlyAdminCalls: false, membersSeeLink: false)
    }
    func saveCard(chatId: String, title: String, description: String) async throws(MaxlyError) {}
    func setPhoto(chatId: String, jpeg: Data) async throws(MaxlyError) {}
    func members(chatId: String) async throws(MaxlyError) -> [ChatAdminPerson] { [] }
    func addMembers(chatId: String, userIds: [String]) async throws(MaxlyError) { added.append(userIds) }
    func removeMember(chatId: String, userId: String) async throws(MaxlyError) {}
    func setAdmin(chatId: String, userId: String, admin: Bool) async throws(MaxlyError) {}
    func revokeInviteLink(chatId: String) async throws(MaxlyError) -> String? {
        link = "https://max.ru/join/new"
        return link
    }
    func joinRequests(chatId: String) async throws(MaxlyError) -> [ChatAdminPerson] { [] }
    func decideJoinRequest(chatId: String, userId: String, accept: Bool) async throws(MaxlyError) {}
    func setOption(chatId: String, option: ChatGroupOption, enabled: Bool) async throws(MaxlyError) {}
    func setComments(chatId: String, enabled: Bool) async throws(MaxlyError) {}
    func blockCommentAuthor(chatId: String, postId: String, userId: String, messageId: String) async throws(MaxlyError) {}
}

private actor LinkMessages: MessageRepository {
    private(set) var sent: [String] = []
    nonisolated func messages(chatId: String) -> AsyncStream<[Message]> { AsyncStream { _ in } }
    func loadOlder(chatId: String) async throws(MaxlyError) -> Bool { false }
    func loadMore(chatId: String, before: Date?) async throws(MaxlyError) -> [Message] { [] }
    func fetchLatest(chatId: String) async throws(MaxlyError) {}
    func send(text: String, chatId: String, replyTo: String?) async throws(MaxlyError) { sent.append("\(chatId) \(text)") }
    func retry(messageId: String) async throws(MaxlyError) {}
    func reactionCatalog() async -> [String] { [] }
}

@Suite("Настройка нового канала как в Max")
@MainActor
struct ChannelSetupModelTests {
    @Test("Ссылка, отправка, сброс, подписчики")
    func flow() async {
        let admin = SetupAdmin()
        let messages = LinkMessages()
        let contacts = FakeContactSource([
            Contact(id: "1", firstName: "Я"),
            Contact(id: "6", firstName: "Маша"),
            Contact(id: "7", firstName: "Бот", isBot: true),
            Contact(id: "8", firstName: "Андрей"),
        ])
        let model = ChannelSetupModel(chatId: "91", title: "Новости", admin: admin, messages: messages, contacts: contacts, currentUserId: "1")
        await model.start()
        #expect(model.shortLink == "max.ru/join/abc")
        #expect(model.people.map(\.displayName) == ["Андрей", "Маша"])

        model.askPublic()
        #expect(model.publicNotice == .public)
        model.publicNotice = nil

        await model.sendLink(to: "5")
        #expect(await messages.sent == ["5 https://max.ru/join/abc"])
        #expect(model.notice == "Ссылка отправлена")
        await model.revokeLink()
        #expect(model.shortLink == "max.ru/join/new")

        model.next()
        #expect(model.step == .subscribers)
        model.query = "маш"
        #expect(model.shown.map(\.displayName) == ["Маша"])
        await model.addSubscribers()
        #expect(await admin.added.isEmpty)
        model.toggle("6")
        model.toggle("8")
        model.toggle("8")
        await model.addSubscribers()
        #expect(await admin.added == [["6"]])
        #expect(model.done)
    }
}
