import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Список чатов: точка «в сети»")
@MainActor
struct ChatListPresenceTests {
    @Test("Собеседник личного чата — id чата ^ свой id; статус спрашивается и ставит точку")
    func dialogDot() async {
        let presence = FakePresence()
        let repository = FakeChatRepository()
        let model = ChatListViewModel(chats: repository, now: { Date(timeIntervalSince1970: 1_790_683_200) })
        model.presence = presence
        model.currentUserId = "1"
        model.activate()
        // Личный чат «3» с собой «1» — собеседник «2»; группа без собеседника.
        repository.emit([chat("3", at: 200, type: .private), chat("-5", at: 100)])
        #expect(await eventually { await presence.refreshed == [["2"]] })
        #expect(model.items.first { $0.id == "3" }?.isOnline == false)
        await presence.push(.online, userId: "2")
        #expect(await eventually { model.items.first { $0.id == "3" }?.isOnline == true })
        #expect(model.items.first { $0.id == "-5" }?.isOnline == false)
        await presence.push(.longAgo, userId: "2")
        #expect(await eventually { model.items.first { $0.id == "3" }?.isOnline == false })
    }

    @Test("У «Избранного» собеседника нет")
    func savedMessages() {
        let model = ChatListViewModel(chats: FakeChatRepository())
        model.currentUserId = "1"
        #expect(model.peer(of: chat(Chat.savedMessagesId, at: 1, type: .private)) == nil)
        #expect(model.peer(of: chat("3", at: 1, type: .private)) == "2")
        #expect(model.peer(of: chat("3", at: 1)) == nil)
    }
}
