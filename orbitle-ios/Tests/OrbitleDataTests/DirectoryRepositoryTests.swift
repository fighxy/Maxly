import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Контакты и звонки из ядра")
struct DirectoryRepositoryTests {
    private func first<T: Sendable>(_ stream: AsyncStream<T>) async -> [T] {
        var values: [T] = []
        for await value in stream { values.append(value) }
        return values
    }

    /// Первое значение потока, который сам не заканчивается.
    private func next<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
        for await value in stream { return value }
        return nil
    }

    private func coreCall(_ id: String, time: Int64, missed: Bool = true) -> CoreCall {
        CoreCall(id: id, chatId: "7", peerId: "20", title: "Анна", avatarURL: "", isGroup: false,
                 outgoing: false, missed: missed, video: false, hangupType: missed ? "MISSED" : "HUNGUP", duration: 0, timeMs: time)
    }

    @Test("Журнал звонков: загрузка заново раздаёт новый список живым подпискам")
    func callsRefresh() async {
        let core = FakeMaxCore()
        await core.setDirectory(calls: [coreCall("1", time: 2_000), coreCall("2", time: 1_000)])
        let repository = CoreCallHistoryRepository(core: core)
        var iterator = repository.calls().makeAsyncIterator()
        #expect(await iterator.next()?.map(\.id) == ["1", "2"])

        // Звонок «1» удалили на другом устройстве.
        await core.setDirectory(calls: [coreCall("2", time: 1_000)])
        await repository.refresh()
        #expect(await iterator.next()?.map(\.id) == ["2"])

        // Новая подписка сразу получает известный список, затем свежий.
        var second = repository.calls().makeAsyncIterator()
        #expect(await second.next()?.map(\.id) == ["2"])
        #expect(await second.next()?.map(\.id) == ["2"])
        // Эта загрузка досталась и первой подписке.
        #expect(await iterator.next()?.map(\.id) == ["2"])

        // Упавшая загрузка не затирает известный список.
        await core.setDirectory(error: CoreFailure(kind: "NETWORK", key: nil))
        await repository.refresh()
        await core.setDirectory(calls: [coreCall("3", time: 3_000)])
        await repository.refresh()
        #expect(await iterator.next()?.map(\.id) == ["3"])

        // После выхода прежний список новой подписке не достаётся.
        await repository.reset()
        await core.setDirectory(error: CoreFailure(kind: "NETWORK", key: nil))
        var third = repository.calls().makeAsyncIterator()
        #expect(await third.next() == [])
    }

    @Test("Журнал звонков: удаление уходит на сервер и сразу пропадает из списка")
    func callsDelete() async throws {
        let core = FakeMaxCore()
        await core.setDirectory(calls: [coreCall("1", time: 2_000), coreCall("2", time: 1_000)])
        let repository = CoreCallHistoryRepository(core: core)
        #expect(repository.capabilities.contains(.delete))
        var iterator = repository.calls().makeAsyncIterator()
        #expect(await iterator.next()?.map(\.id) == ["1", "2"])
        try await repository.delete(ids: ["1", "звонок"])
        #expect(await core.deletedCalls == [["1"]])
        #expect(await iterator.next()?.map(\.id) == ["2"])

        await core.setDirectory(calls: [coreCall("2", time: 1_000)], error: CoreFailure(kind: "NETWORK", key: nil))
        await #expect(throws: OrbitleError.networkUnavailable) { try await repository.delete(ids: ["2"]) }
    }

    @Test("Звонки из ядра: адрес ws2, свой номер, ICE и срок входящего")
    func callService() throws {
        let incoming = try #require(CoreCallService.incoming(CoreIncomingCall(
            conversationId: "c", callerId: "5", callerName: "Анна", chatId: "", isVideo: true,
            ws2Url: "wss://sig.test/ws?userId=9", callsUserId: 9, stunUrls: ["stun:a"], turnUrls: ["turn:b"],
            turnUsername: "u", turnPassword: "p", expiresAtMs: 1_700_000_000_000
        )))
        #expect(incoming.connection.selfId == 9)
        #expect(incoming.connection.signalingURL.absoluteString == "wss://sig.test/ws?userId=9")
        #expect(incoming.connection.iceServers == [
            CallIceServer(urls: ["stun:a"]),
            CallIceServer(urls: ["turn:b"], username: "u", credential: "p"),
        ])
        #expect(incoming.expiresAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(incoming.chatId == nil)
        #expect(incoming.isVideo)
        #expect(CoreCallService.incoming(CoreIncomingCall(conversationId: "", callerId: "5", ws2Url: "wss://s", callsUserId: 1)) == nil)

        let start = try CoreCallService.connection(CoreCallStart(
            conversationId: "c", ws2Url: "wss://sig.test/ws?tgt=start", callsUserId: 3, joinLink: "https://max.ru/joincall/t"
        ))
        #expect(start.selfId == 3)
        #expect(start.joinLink?.absoluteString == "https://max.ru/joincall/t")
        #expect(throws: OrbitleError.invalidRequest) {
            try CoreCallService.connection(CoreCallStart(conversationId: "c", ws2Url: "https://sig.test", callsUserId: 3))
        }
    }

    @Test("Отметки звонков: у каждого аккаунта свои, выход их стирает")
    @MainActor
    func callMarks() throws {
        let suite = "orbitle.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UserDefaultsCallHistoryMarks(userId: "1", defaults: defaults)
        #expect(first.lastSeen == nil)
        first.lastSeen = Date(timeIntervalSince1970: 1_000)
        first.hiddenIds = ["a", "b"]
        let again = UserDefaultsCallHistoryMarks(userId: "1", defaults: defaults)
        #expect(again.lastSeen == Date(timeIntervalSince1970: 1_000))
        #expect(again.hiddenIds == ["a", "b"])
        let other = UserDefaultsCallHistoryMarks(userId: "2", defaults: defaults)
        #expect(other.lastSeen == nil)
        #expect(other.hiddenIds.isEmpty)
        UserDefaultsCallHistoryMarks.erase(userId: "1", defaults: defaults)
        #expect(again.lastSeen == nil)
        #expect(again.hiddenIds.isEmpty)
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

    @Test("Статусы контактов и карточки собеседника уходят в общий PresenceStore, неизвестные — нет")
    func presenceFeed() async throws {
        let core = FakeMaxCore()
        await core.setDirectory(contacts: [
            CoreContact(id: "20", firstName: "Анна", lastName: "", phone: "", avatarURL: "", lastSeenMs: 0, online: true),
            CoreContact(id: "30", firstName: "Борис", lastName: "", phone: "", avatarURL: "", lastSeenMs: 1_000, online: false),
            CoreContact(id: "40", firstName: "Вера", lastName: "", phone: "", avatarURL: "", lastSeenMs: 0, online: false),
        ])
        let presence = PresenceStore()
        let repository = CoreContactRepository(core: core, presence: presence)
        _ = await first(repository.contacts())
        #expect(await presence.isOnline("20"))
        #expect(await presence.presence(of: "30") == .lastSeen(Date(unixMillis: 1_000)))
        #expect(await presence.presence(of: "40") == nil)
    }

    @Test("Первое открытие списка запускает полную синхронизацию: ядро после входа знает не всех")
    func contactsSyncOnFirstFeed() async {
        let core = FakeMaxCore()
        let anna = CoreContact(id: "20", firstName: "Анна", lastName: "", phone: "", avatarURL: "", lastSeenMs: 0, online: false)
        let boris = CoreContact(id: "30", firstName: "Борис", lastName: "", phone: "", avatarURL: "", lastSeenMs: 0, online: false)
        // После входа с отметкой синхронизации ядро знает только изменения.
        await core.setDirectory(contacts: [anna])
        await core.setSyncedContacts([anna, boris])
        let repository = CoreContactRepository(core: core)
        // Что уже есть — сразу, полный список следом.
        #expect(await first(repository.contacts()).map { $0.map(\.id) } == [["20"], ["20", "30"]])
        #expect(await core.contactSyncs == 1)
        // Дальше полная синхронизация не повторяется: кэш и список ядра.
        await core.setDirectory(contacts: [anna, boris])
        #expect(await first(repository.contacts()).map { $0.map(\.id) } == [["20", "30"], ["20", "30"]])
        #expect(await core.contactSyncs == 1)
        // Новый сеанс — снова полная синхронизация.
        await repository.reset()
        _ = await first(repository.contacts())
        #expect(await core.contactSyncs == 2)
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
        let list = await next(repository.calls()) ?? []
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
        #expect(channel.commentsEnabled == nil)
        let quiet = CoreMapping.profile(CoreProfile(kind: "channel", chatId: "-10", commentsEnabled: false))
        #expect(quiet.commentsEnabled == false)
    }
}
