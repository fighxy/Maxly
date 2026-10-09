import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Сообщение с серверным id `id` и временем `id` секунд.
private func message(_ id: Int, author: String = "bob", status: MessageStatus = .sent) -> Message {
    Message(
        id: "\(id)", serverId: "\(id)", chatId: "c", authorId: author, text: "m\(id)",
        timestamp: Date(timeIntervalSince1970: Double(id)), status: status
    )
}

private func messages(_ ids: ClosedRange<Int>) -> [Message] {
    ids.map { message($0) }
}

@Suite("Окно перехода")
struct TimelineWindowTests {
    @Test("Страницы ложатся по краям, по времени и без повторов")
    func paging() {
        var window = TimelineWindow([message(12), message(10), message(11)])
        #expect(window.messages.map(\.id) == ["10", "11", "12"])
        #expect(window.prepend([message(9), message(10), message(8)]) == 2)
        #expect(window.append([message(12), message(13)]) == 1)
        #expect(window.messages.map(\.id) == ["8", "9", "10", "11", "12", "13"])
        #expect(window.prepend([]) == 0)
        #expect(window.append([message(3)]) == 0)
    }

    @Test("Сходится с живой лентой по общему сообщению или по времени")
    func meets() {
        let window = TimelineWindow([message(10), message(11)])
        #expect(!window.meets(messages(20...21)))
        #expect(window.meets(messages(11...12)))
        #expect(TimelineWindow([message(10), message(25)]).meets(messages(20...21)))
        #expect(!window.meets([]))
        // Своё неотправленное стоит в конце живой ленты и её не старит.
        #expect(!window.meets([message(5, author: "me", status: .sending)]))
    }

    @Test("Слившись, окно держит живую ленту снизу и не теряет ушедшее из неё сверху")
    func absorb() {
        var window = TimelineWindow(messages(1...3))
        window.join(messages(3...5))
        #expect(window.joined)
        #expect(window.messages.map(\.id) == ["1", "2", "3", "4", "5"])
        // Живая лента держит последние N: 3 ушло сверху, пришло 6.
        window.absorb(messages(4...6))
        #expect(window.messages.map(\.id) == ["1", "2", "3", "4", "5", "6"])
        // 5 удалили.
        window.absorb([message(4), message(6)])
        #expect(window.messages.map(\.id) == ["1", "2", "3", "4", "6"])
        // Пустая живая лента окно не стирает.
        window.absorb([])
        #expect(window.messages.count == 5)
    }
}

@Suite("Положение в ленте чата")
@MainActor
struct ChatPositionTests {
    /// Открытый чат: сверка закончена, живая лента пришла подпиской.
    private func opened(_ repository: FakeMessageRepository, unread: Int = 0, feed: [Message]) async -> ChatViewModel {
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.noteUnreadOnOpen(unread)
        await model.loadLatest()
        model.activate()
        repository.emit(feed)
        _ = await eventually { model.messages.count == feed.count }
        return model
    }

    @Test("Цитата в ленте: прокрутка к ней с подсветкой, без запроса к серверу")
    func jumpInsideFeed() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(1...5))
        await model.jump(to: "2", from: "5")
        #expect(model.scrollTarget == .message("2", highlight: true))
        #expect(model.highlightedId == "2")
        #expect(!model.isJumped)
        #expect(await repository.aroundRequests.isEmpty)
        model.consumeScroll()
        #expect(model.scrollTarget == nil)
        model.deactivate()
    }

    @Test("Далёкая цитата: окно вокруг неё, «вниз» возвращает к сообщению, с которого перешли")
    func jumpFarAndBack() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(50...55))
        await repository.queueAround(messages(5...15))
        await model.jump(to: "10", from: "55")
        #expect(await repository.aroundRequests == [FakeMessageRepository.AroundRequest(messageId: "10", at: nil, forward: 35, backward: 25)])
        #expect(model.isJumped)
        #expect(model.messages.map(\.id) == messages(5...15).map(\.id))
        #expect(model.scrollTarget == .message("10", highlight: true))

        #expect(model.returnFromJump())
        #expect(!model.isJumped)
        #expect(model.messages.map(\.id) == messages(50...55).map(\.id))
        #expect(model.scrollTarget == .message("55", highlight: false))
        #expect(!model.returnFromJump())
        model.deactivate()
    }

    @Test("Из окна без возврата «вниз» ведёт к живой ленте; найденное ищется по времени")
    func downFromWindow() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(50...55))
        await repository.queueAround(messages(5...15))
        await model.jump(to: "10", at: Date(timeIntervalSince1970: 10))
        #expect(await repository.aroundRequests.first?.at == Date(timeIntervalSince1970: 10))
        #expect(model.returnFromJump())
        #expect(model.scrollTarget == .bottom)
        #expect(!model.isJumped)
        #expect(model.messages.map(\.id) == messages(50...55).map(\.id))
        model.deactivate()
    }

    @Test("Листая окно вниз, лента доходит до живой и снова следует за ней")
    func newerPagesJoinLive() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(20...25))
        await repository.queueAround(messages(5...15))
        await model.jump(to: "10")
        await repository.queueAround(messages(16...21))
        await model.loadNewer()
        let requests = await repository.aroundRequests
        #expect(requests.last == FakeMessageRepository.AroundRequest(messageId: "15", at: Date(timeIntervalSince1970: 15), forward: 40, backward: 0))
        #expect(!model.isJumped)
        #expect(model.messages.map(\.id) == messages(5...25).map(\.id))
        // Живая лента сдвинулась: окно держит её внизу, ушедшее сверху остаётся.
        repository.emit(messages(21...26))
        _ = await eventually { model.messages.last?.id == "26" }
        #expect(model.messages.map(\.id) == messages(5...26).map(\.id))
        model.deactivate()
    }

    @Test("Листая окно вверх, лента доходит до начала истории")
    func olderPagesInWindow() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(50...55))
        await repository.queueAround(messages(5...15))
        await model.jump(to: "10")
        await repository.queueAround(messages(1...5))
        await model.loadOlder()
        #expect(model.messages.map(\.id) == messages(1...15).map(\.id))
        #expect(model.canLoadOlder)
        await repository.queueAround([message(1)])
        await model.loadOlder()
        #expect(!model.canLoadOlder)
        #expect(model.isJumped)
        model.deactivate()
    }

    @Test("Удалённое сообщение: уведомление, лента на месте; ошибка сервера видна")
    func notFound() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(50...55))
        await repository.queueAround(messages(5...9))
        await model.jump(to: "10")
        #expect(model.notice == "Сообщение не найдено")
        #expect(!model.isJumped)
        #expect(model.scrollTarget == nil)
        await model.jump(to: "11")
        #expect(model.error == .networkUnavailable)
        // Своё неотправленное, которого нет в ленте, у сервера не ищется.
        await model.jump(to: "local-1")
        #expect(await repository.aroundRequests.count == 2)
        model.deactivate()
    }

    @Test("Своё сообщение из окна перехода возвращает к живой ленте вниз")
    func sendLeavesWindow() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(50...55))
        await repository.queueAround(messages(5...15))
        await model.jump(to: "10")
        model.draft = "Привет"
        await model.send()
        #expect(!model.isJumped)
        #expect(model.scrollTarget == .bottom)
        #expect(await repository.sent == ["Привет"])
        model.deactivate()
    }

    @Test("Счётчик «вниз»: непрочитанные под разделителем, меньше по мере чтения, новые сверху")
    func unreadBelow() async {
        let repository = FakeMessageRepository()
        let feed = [message(1), message(2, author: "me"), message(3), message(4)]
        let model = await opened(repository, unread: 2, feed: feed)
        #expect(model.unreadAnchorId == "3")
        #expect(model.unreadBelow == 2)
        model.noteBottomVisible("3")
        #expect(model.unreadBelow == 1)
        // Прокрутка вверх отметку не опускает.
        model.noteBottomVisible("1")
        #expect(model.unreadBelow == 1)
        model.noteAtBottom()
        #expect(model.unreadBelow == 0)
        repository.emit(feed + [message(5)])
        _ = await eventually { model.messages.count == 5 }
        #expect(model.unreadBelow == 1)
        model.deactivate()
    }

    @Test("Непрочитанных больше окна: окно растёт страницами до первого из них")
    func reachUnread() async {
        let repository = FakeMessageRepository()
        // Первая страница кэша (новые сверху), затем страница старше.
        await repository.queueMore([message(8), message(7), message(6)])
        await repository.queueMore([message(5), message(4), message(3)])
        await repository.queueMore([message(2), message(1)])
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.noteUnreadOnOpen(5)
        await model.loadLatest()
        #expect(await repository.olderLoads == 1)
    }

    @Test("Из общего поиска: чат открывается на найденном сообщении, открытый — переходит сразу")
    func openAtFound() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.openAt(messageId: "2")
        #expect(model.hasPendingOpen)
        model.noteUnreadOnOpen(0)
        await model.loadLatest()
        model.activate()
        repository.emit(messages(1...5))
        _ = await eventually { model.messages.count == 5 }
        model.startPendingOpen()
        #expect(!model.hasPendingOpen)
        #expect(await eventually { model.scrollTarget == .message("2", highlight: true) })
        model.consumeScroll()
        model.openAt(messageId: "4")
        #expect(!model.hasPendingOpen)
        #expect(await eventually { model.scrollTarget == .message("4", highlight: true) })
        model.deactivate()
    }

    @Test("Место в ленте: помнится посреди истории, внизу — нет")
    func savedPlace() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(1...5))
        model.savePlace("3", atBottom: false)
        #expect(model.restoredPlace == "3")
        model.savePlace("3", atBottom: true)
        #expect(model.restoredPlace == nil)
        model.savePlace("99", atBottom: false)
        #expect(model.restoredPlace == nil)
        model.deactivate()
    }

    @Test("Плашка даты берёт верхнюю из видимых строк")
    func topRow() async {
        let repository = FakeMessageRepository()
        let model = await opened(repository, feed: messages(1...5))
        #expect(model.topRow(among: ["4", "transcript-bottom", "2"]) == "2")
        #expect(model.topRow(among: ["transcript-bottom"]) == nil)
        let now = Date(timeIntervalSince1970: 3)
        #expect(model.dayTitle(ofRow: "2", now: now) == ChatContentFormat.dayTitle(Date(timeIntervalSince1970: 2), now: now))
        #expect(model.dayTitle(ofRow: nil) == nil)
        model.deactivate()
    }
}
