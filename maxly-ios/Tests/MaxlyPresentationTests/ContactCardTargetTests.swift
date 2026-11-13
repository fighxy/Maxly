import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Карточка контакта: куда ведёт нажатие")
struct ContactCardTargetTests {
    @Test func accountOpensProfile() {
        let contact = ContactContent(id: "a1", userId: "42", name: "Сисадмин", phone: "79991234567")
        let target = ContactCardTarget.resolve(contact, me: "7")
        #expect(target == .profile(DialogDraft(chatId: String(Int64(7) ^ Int64(42)), peerId: "42", title: "Сисадмин")))
    }

    @Test func phoneOnlyOffersCall() {
        let contact = ContactContent(id: "a1", userId: "", name: "Дмитрий", phone: "79963771095")
        guard case .phone(let display, let call) = ContactCardTarget.resolve(contact, me: "7") else {
            Issue.record("ожидался номер")
            return
        }
        #expect(display.hasPrefix("+7"))
        #expect(call == URL(string: "tel:+79963771095"))
    }

    @Test func ownCardFallsBackToPhone() {
        let contact = ContactContent(id: "a1", userId: "7", name: "Я", phone: "+7 999 000-00-00")
        guard case .phone(_, let call) = ContactCardTarget.resolve(contact, me: "7") else {
            Issue.record("ожидался номер")
            return
        }
        #expect(call == URL(string: "tel:+79990000000"))
    }

    @Test func nothingToOpen() {
        #expect(ContactCardTarget.resolve(ContactContent(id: "a1", userId: "", name: "Без номера"), me: "7") == nil)
    }
}
