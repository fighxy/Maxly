import Foundation
import Testing
@testable import OrbitleDomain

@Suite("Аккаунт и настройки")
struct AccountTests {
    @Test("Российский номер форматируется, остальные — плюс и цифры")
    func phoneFormat() {
        #expect(PhoneFormatting.format("79990001122") == "+7 999 000-11-22")
        #expect(PhoneFormatting.format("89990001122") == "+7 999 000-11-22")
        #expect(PhoneFormatting.format("+375 29 1234567") == "+375291234567")
        #expect(PhoneFormatting.format("") == "")
    }

    @Test("Скрытый номер: код страны виден, цифры — точки, форма та же")
    func phoneMask() {
        #expect(PhoneFormatting.mask("+7 999 000-11-22") == "+7 ••• •••-••-••")
        #expect(PhoneFormatting.mask("+375291234567") == "+3•••••••••••")
        #expect(PhoneFormatting.mask("") == "")
        let profile = MyProfile(id: "1", firstName: "Иван", phone: "79990001122")
        #expect(profile.maskedPhone.count == profile.formattedPhone.count)
        #expect(!profile.maskedPhone.contains("9"))
    }

    @Test("Имя в шапке: имя и фамилия, пустое — «Без имени»")
    func displayName() {
        #expect(MyProfile(id: "1", firstName: "Иван", lastName: "Петров").displayName == "Иван Петров")
        #expect(MyProfile(id: "1", firstName: " ", lastName: "").displayName == "Без имени")
    }

    @Test("Почта для восстановления скрыта, домен виден")
    func emailMask() {
        #expect(TwoFactorStatus.mask(email: "ivan@ya.ru") == "i•••n@ya.ru")
        #expect(TwoFactorStatus.mask(email: "ab@ya.ru") == "a•••@ya.ru")
        #expect(TwoFactorStatus.mask(email: "broken") == "broken")
        #expect(TwoFactorStatus(isEnabled: true, email: "").email == nil)
    }

    @Test("Возврат внешнего шага мини-приложения узнаётся по externalCallback=1")
    func externalCallback() throws {
        #expect(MiniApp.isExternalCallback(try #require(URL(string: "https://digital-id.max.ru/cb?externalCallback=1&code=x"))))
        #expect(!MiniApp.isExternalCallback(try #require(URL(string: "https://digital-id.max.ru/cb?externalCallback=0"))))
        #expect(!MiniApp.isExternalCallback(try #require(URL(string: "https://gosuslugi.ru/"))))
    }

    @Test("Сеанс без приложения и устройства называется «Неизвестное устройство»")
    func sessionTitle() {
        #expect(DeviceSession(id: "1", client: "MAX Web").title == "MAX Web")
        #expect(DeviceSession(id: "1", client: "", info: "Safari").title == "Safari")
        #expect(DeviceSession(id: "1", client: "").title == "Неизвестное устройство")
    }
}

@Suite("Правила серверных папок")
struct ServerFolderRulesTests {
    private func chat(_ id: String, _ type: ChatType, bot: Bool = false, unread: Int = 0, muted: Bool = false, archived: Bool = false) -> Chat {
        Chat(id: id, title: id, type: type, unreadCount: unread, updatedAt: Date(), isMuted: muted, isArchived: archived, isBot: bot)
    }

    private var all: [Chat] {
        [
            chat("p", .private),
            chat("pu", .private, unread: 2),
            chat("g", .group),
            chat("gm", .group, unread: 1, muted: true),
            chat("c", .channel),
            chat("b", .private, bot: true),
            chat(Chat.savedMessagesId, .private),
            chat("arch", .private, archived: true),
        ]
    }

    private func ids(_ filters: [String], chats chatIds: [String] = []) -> [String] {
        let folder = ServerFolder(id: "f", title: "F", chatIds: chatIds, filters: filters).chatFolder
        return all.filter(folder.contains).map(\.id)
    }

    @Test("Типы объединяются по «или»")
    func types() {
        #expect(ids(["4"]) == ["p", "pu"])
        #expect(ids(["2"]) == ["c"])
        #expect(ids(["10"]) == ["b"])
        #expect(ids(["2", "3"]) == ["g", "gm", "c"])
        #expect(ids(["CHANNEL", "bot"]) == ["c", "b"])
    }

    @Test("Состояния сужают по «и»")
    func states() {
        #expect(ids(["0"]) == ["pu", "gm"])
        #expect(ids(["3", "0"]) == ["gm"])
        #expect(ids(["3", "11"]) == ["g"])
        #expect(ids(["7"]) == ["gm"])
    }

    @Test("Явные чаты входят всегда, кроме архива; без правил папка пуста")
    func explicit() {
        #expect(ids([], chats: ["g", "arch"]) == ["g"])
        #expect(ids(["10"], chats: ["c"]) == ["c", "b"])
        #expect(ids([]) == [])
        #expect(ids(["5", "6", "13", "999", "x"]) == [])
    }
}
