import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private struct OneProfile: ChatProfileRepository {
    let card: ChatProfile
    func profile(chatId: String) async throws(MaxlyError) -> ChatProfile { card }
}

private actor FakeActions: ProfileActionsRepository {
    var blocked: Set<String> = []
    private(set) var complaints: [(ComplaintTarget, Int)] = []
    private(set) var memberCalls = 0
    private(set) var commonCalls = 0

    func members(chatId: String) async throws(MaxlyError) -> [ProfileMember] {
        memberCalls += 1
        return [ProfileMember(id: "5", name: "Анна")]
    }

    func commonChats(userId: String) async throws(MaxlyError) -> [CommonChat] {
        commonCalls += 1
        return [CommonChat(id: "-1", title: "Семья", isChannel: false, participants: 3)]
    }

    func complaintReasons(for target: ComplaintTarget) async throws(MaxlyError) -> [ComplaintReason] {
        [ComplaintReason(id: 1, title: "Спам")]
    }

    func complain(about target: ComplaintTarget, reasonId: Int) async throws(MaxlyError) -> Bool {
        complaints.append((target, reasonId))
        return true
    }

    func isBlocked(userId: String) async throws(MaxlyError) -> Bool { blocked.contains(userId) }

    func setBlocked(userId: String, blocked flag: Bool) async throws(MaxlyError) {
        if flag { blocked.insert(userId) } else { blocked.remove(userId) }
    }
}

@Suite("Действия профиля")
@MainActor
struct ProfileActionsTests {
    @Test("Собеседник: общие чаты, блокировка и жалоба на него")
    func person() async {
        let actions = FakeActions()
        let card = ChatProfile(kind: .user, chatId: "12", peerId: "7", title: "Олег")
        let model = ChatProfileViewModel(chatId: "12", title: "Олег", repository: OneProfile(card: card), actions: actions)
        await model.load()
        await model.loadExtras()
        await model.loadExtras()
        #expect(model.commonChats.map(\.title) == ["Семья"])
        #expect(await actions.commonCalls == 1)
        #expect(model.isBlocked == false)
        #expect(model.canBlock)
        #expect(model.complaintTarget == .user("7"))

        await model.toggleBlocked()
        #expect(model.isBlocked == true)
        #expect(await actions.blocked == ["7"])
        #expect(model.actionNotice == "Пользователь заблокирован")

        #expect(await model.loadComplaintReasons())
        await model.complain(reasonId: 1)
        #expect(await actions.complaints.map(\.0) == [.user("7")])
        #expect(model.actionNotice == "Жалоба отправлена")
    }

    @Test("Группа: участники, без блокировки и жалобы; канал — жалоба на сам канал")
    func groupAndChannel() async {
        let actions = FakeActions()
        let group = ChatProfileViewModel(chatId: "-3", title: "Семья", repository: OneProfile(card: ChatProfile(kind: .group, chatId: "-3", title: "Семья")), actions: actions)
        await group.load()
        await group.loadExtras()
        #expect(group.members.map(\.name) == ["Анна"])
        #expect(!group.canBlock)
        #expect(group.complaintTarget == nil)

        let channel = ChatProfileViewModel(chatId: "-9", title: "Новости", repository: OneProfile(card: ChatProfile(kind: .channel, chatId: "-9", title: "Новости")), actions: actions)
        await channel.load()
        await channel.loadExtras()
        #expect(channel.complaintTarget == .channel("-9"))
        #expect(await actions.memberCalls == 1)
        #expect(ChatProfileViewModel.membersText(3, channel: false) == "3 участника")
    }
}
