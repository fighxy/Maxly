import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlData

@Suite("Контакты и звонки из ядра")
struct DirectoryRepositoryTests {
    private func first<T: Sendable>(_ stream: AsyncStream<T>) async -> [T] {
        var values: [T] = []
        for await value in stream { values.append(value) }
        return values
    }

    @Test("Контакты приходят из ядра, со статусом и номером")
    func contacts() async {
        let core = FakeMaxCore()
        await core.setDirectory(contacts: [
            CoreContact(id: "20", firstName: "Анна", lastName: "Ли", phone: "79990000000", avatarURL: "", lastSeenMs: 0, online: true),
            CoreContact(id: "30", firstName: "Борис", lastName: "", phone: "", avatarURL: "https://a/b.jpg", lastSeenMs: 1_000, online: false),
        ])
        let repository = CoreContactRepository(core: core)
        #expect(repository.capabilities.contains(.list))
        let values = await first(repository.contacts())
        #expect(values.count == 1)
        let list = values[0]
        #expect(list.map(\.id) == ["20", "30"])
        #expect(list[0].presence == .online)
        #expect(list[0].phone == "+79990000000")
        #expect(list[1].presence == .lastSeen(Date(unixMillis: 1_000)))
        #expect(list[1].phone == nil)
        #expect(list[1].avatarURL == URL(string: "https://a/b.jpg"))
    }

    @Test("Ошибка ядра не оставляет экран в загрузке, кэш показывается сразу")
    func contactsCacheAndError() async {
        let core = FakeMaxCore()
        let repository = CoreContactRepository(core: core)
        await core.setDirectory(error: CoreFailure(kind: "NETWORK", key: nil))
        #expect(await first(repository.contacts()) == [[]])
        await core.setDirectory(contacts: [CoreContact(id: "20", firstName: "А", lastName: "", phone: "", avatarURL: "", lastSeenMs: 0, online: false)])
        _ = await first(repository.contacts())
        await core.setDirectory(error: CoreFailure(kind: "NETWORK", key: nil))
        // Кэш приходит первым, а упавшая загрузка не затирает его пустым списком.
        #expect(await first(repository.contacts()).map { $0.map(\.id) } == [["20"]])
        await repository.reset()
        #expect(await first(repository.contacts()) == [[]])
    }

    @Test("Журнал звонков: направление, исход, группа, новые сверху")
    func calls() async {
        let core = FakeMaxCore()
        func call(_ id: String, outgoing: Bool, missed: Bool = false, hangup: String = "HUNGUP", duration: Int64 = 0, time: Int64, group: Bool = false) -> CoreCall {
            CoreCall(id: id, chatId: "7", peerId: group ? "" : "20", title: group ? "" : "Анна", avatarURL: "", isGroup: group,
                     outgoing: outgoing, missed: missed, video: id == "1", hangupType: hangup, duration: duration, timeMs: time)
        }
        await core.setDirectory(calls: [
            call("1", outgoing: true, duration: 60_000, time: 1_000),
            call("2", outgoing: false, missed: true, hangup: "MISSED", time: 3_000),
            call("3", outgoing: true, hangup: "REJECTED", time: 2_000),
            call("4", outgoing: true, hangup: "CANCELED", time: 500, group: true),
        ])
        let repository = CoreCallHistoryRepository(core: core)
        let list = await first(repository.calls()).last ?? []
        #expect(list.map(\.id) == ["2", "3", "1", "4"])
        #expect(list[0].isMissed)
        #expect(list[1].outcome == .declined)
        #expect(list[2].outcome == .answered)
        #expect(list[2].isVideo)
        #expect(list[3].outcome == .cancelled)
        #expect(list[3].isGroup)
        #expect(list[3].title == "Групповой звонок")
        #expect(list[3].peerId == "7")
    }

    @Test("Карточка из ядра: пустые поля становятся nil, номер получает плюс")
    func profileMapping() {
        let bot = CoreMapping.profile(CoreProfile(
            kind: "bot", chatId: "5", peerId: "77", title: "Помощник", description: "  ", link: "helper_bot",
            official: true, commands: [.init(name: "start", description: "Начать"), .init(name: "help", description: "")]
        ))
        #expect(bot.kind == .bot)
        #expect(bot.peerId == "77")
        #expect(bot.description == nil)
        #expect(bot.linkURL == URL(string: "https://max.ru/helper_bot"))
        #expect(bot.isOfficial)
        #expect(bot.commands == [.init(name: "start", description: "Начать"), .init(name: "help")])
        let user = CoreMapping.profile(CoreProfile(kind: "user", chatId: "13", phone: "79991234567", lastSeenMs: 1_000))
        #expect(user.phone == "+79991234567")
        #expect(user.presence == .lastSeen(Date(unixMillis: 1_000)))
        #expect(user.participants == nil)
        let channel = CoreMapping.profile(CoreProfile(kind: "channel", chatId: "-9", participants: 12))
        #expect(channel.kind == .channel)
        #expect(channel.peerId == nil)
        #expect(channel.participants == 12)
    }
}
