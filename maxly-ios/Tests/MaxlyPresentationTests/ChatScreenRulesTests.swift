import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

private func rules(
    _ type: ChatType,
    canWrite: Bool?,
    card: ChatProfile.Kind? = nil,
    _ edit: (inout ChatScreenRules.Input) -> Void = { _ in }
) -> ChatScreenRules {
    var input = ChatScreenRules.Input(listedType: type, canWrite: canWrite, card: card)
    edit(&input)
    return ChatScreenRules(input)
}

@Suite("Экран чата: правила по виду чата")
struct ChatScreenRulesTests {
    @Test("Диалог: поле ввода, без авторов и «@», звонок, закреп «только у меня»")
    func dialog() {
        let dialog = rules(.private, canWrite: true, card: .user)
        #expect(dialog.kind == .private)
        #expect(dialog.bottomBar == .composer)
        #expect(!dialog.showsAuthors)
        #expect(!dialog.showsMentionsButton)
        #expect(dialog.canCall)
        #expect(!dialog.canLeave)
        #expect(dialog.pinOptions == .dialog)
        #expect(dialog.deleteForAllTitle == "Удалить у меня и у собеседника")
    }

    @Test("Группа: авторы, кто поставил реакцию, «@», выход, закреп с уведомлением")
    func group() {
        let group = rules(.group, canWrite: true, card: .group)
        #expect(group.showsAuthors)
        #expect(group.showsReactionUsers)
        #expect(group.showsMentionsButton)
        #expect(group.canLeave)
        #expect(!group.canCall)
        #expect(group.pinOptions == .group)
        #expect(group.deleteForAllTitle == "Удалить у всех")
        let muted = rules(.group, canWrite: false)
        #expect(muted.bottomBar == .readOnly)
    }

    @Test("Канал: подписчик — звук и поиск, админ — поле ввода и «Канал готов»")
    func channel() {
        let reader = rules(.channel, canWrite: false) { $0.canToggleMute = true; $0.commentsEnabled = true }
        #expect(reader.bottomBar == .channelControls)
        #expect(reader.searchInBottomBar)
        #expect(reader.allowsComments)
        #expect(!reader.showsAuthors)
        #expect(!reader.isChannelAdmin)
        #expect(!reader.showsChannelReady)
        let admin = rules(.channel, canWrite: true)
        #expect(admin.bottomBar == .composer)
        #expect(admin.isChannelAdmin)
        #expect(admin.showsChannelReady)
        #expect(!admin.allowsComments)
        #expect(admin.pinOptions == .channel)
    }

    @Test("Вне списка: вид из карточки, «Подписаться» / «Вступить» по ссылке, до карточки ничего")
    func outsideList() {
        let pending = rules(.private, canWrite: nil)
        #expect(!pending.writable)
        #expect(pending.bottomBar == .readOnly)
        let channel = rules(.private, canWrite: nil, card: .channel) { $0.hasJoinLink = true }
        #expect(channel.kind == .channel)
        #expect(channel.bottomBar == .join(label: "Подписаться"))
        #expect(!channel.searchInBottomBar)
        #expect(!channel.canLeave)
        let group = rules(.private, canWrite: nil, card: .group) { $0.hasJoinLink = true }
        #expect(group.bottomBar == .join(label: "Вступить"))
        let closed = rules(.private, canWrite: nil, card: .group)
        #expect(closed.bottomBar == .readOnly)
        let person = rules(.private, canWrite: nil, card: .user)
        #expect(person.writable)
        #expect(person.bottomBar == .composer)
    }

    @Test("Бот: в пустой истории «Начать», с сообщениями — поле ввода")
    func botStart() {
        #expect(rules(.private, canWrite: true, card: .bot) { $0.historyEmpty = true }.bottomBar == .startBot)
        #expect(rules(.private, canWrite: true, card: .bot).bottomBar == .composer)
        // Пустой диалог с человеком — обычное поле ввода.
        #expect(rules(.private, canWrite: true, card: .user) { $0.historyEmpty = true }.bottomBar == .composer)
    }

    @Test("Незнакомец: плашка, пока не в контактах, не заблокирован и не закрыта; «Заблокировать» — пока сам не писал")
    func strangerBar() {
        let fresh = rules(.private, canWrite: true, card: .user) { $0.contactAddable = true }
        #expect(fresh.strangerBar == ChatScreenRules.StrangerBar(offersBlock: true))
        let replied = rules(.private, canWrite: true, card: .user) { $0.contactAddable = true; $0.hasOwnMessages = true }
        #expect(replied.strangerBar == ChatScreenRules.StrangerBar(offersBlock: false))
        #expect(rules(.private, canWrite: true, card: .user).strangerBar == nil)
        #expect(rules(.private, canWrite: true, card: .user) { $0.contactAddable = true; $0.peerBlocked = true }.strangerBar == nil)
        #expect(rules(.private, canWrite: true, card: .user) { $0.contactAddable = true; $0.strangerBarDismissed = true }.strangerBar == nil)
        #expect(rules(.private, canWrite: true, card: .bot) { $0.contactAddable = true }.strangerBar == nil)
        #expect(rules(.group, canWrite: true, card: .group) { $0.contactAddable = true }.strangerBar == nil)
    }
}
