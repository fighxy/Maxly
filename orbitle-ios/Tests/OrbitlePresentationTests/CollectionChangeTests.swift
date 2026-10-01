import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Изменения списков для анимации")
struct CollectionChangeTests {
    private func ids(_ range: ClosedRange<Int>) -> [String] { range.map(String.init) }

    @Test("Одинаковые списки и первая загрузка не анимируются")
    func noneAndInitial() {
        #expect(CollectionChange.between(["a"], ["a"]) == .none)
        #expect(CollectionChange.between([], []) == .none)
        #expect(CollectionChange.between([], ids(1...50)) == .initial)
        #expect(!CollectionChange.initial.animatesTranscript)
        #expect(!CollectionChange.initial.animatesList)
    }

    @Test("Новое сообщение снизу анимируется, даже если окно сдвинулось")
    func appended() {
        #expect(CollectionChange.between(ids(1...3), ids(1...4)) == .appended(1))
        // Окно держит 50 последних: сверху ушло одно, снизу пришло одно.
        let change = CollectionChange.between(ids(1...50), ids(2...51))
        #expect(change == .appended(1))
        #expect(change.animatesTranscript)
    }

    @Test("Крупный сдвиг окна не маскируется одной новой вставкой")
    func largeWindowShift() {
        let change = CollectionChange.between(ids(1...100), ids(95...101))
        #expect(change == .reload)
        #expect(!change.animatesTranscript)
    }

    @Test("Старая страница сверху не анимируется в ленте")
    func prependedHistory() {
        let change = CollectionChange.between(ids(51...100), ids(1...100))
        #expect(change == .prepended(50))
        #expect(!change.animatesTranscript)
    }

    @Test("Удаление из середины анимируется, окно сверху подтягивает старое")
    func removed() {
        #expect(CollectionChange.between(["1", "2", "3"], ["1", "3"]) == .removed(1))
        #expect(CollectionChange.between(["1", "2", "3"], ["1", "3"]).animatesTranscript)
        // Полное окно: удалили 25-е, сверху подтянулось 0-е.
        let full = CollectionChange.between(ids(1...50), ["0"] + ids(1...24) + ids(26...50))
        #expect(full == .updated(2))
        #expect(full.animatesTranscript)
    }

    @Test("Удаление последних сообщений чата — удаление, а не замена")
    func removedAll() {
        #expect(CollectionChange.between(["1", "2"], []) == .removed(2))
        #expect(CollectionChange.between(ids(1...50), []) == .reload)
    }

    @Test("Уход только верхних — сужение окна, без анимации")
    func trimmed() {
        let change = CollectionChange.between(ids(1...100), ids(51...100))
        #expect(change == .trimmed(50))
        #expect(!change.animatesTranscript)
    }

    @Test("Подъём чата с новым сообщением — одна перестановка, анимируется в списке")
    func moved() {
        let change = CollectionChange.between(["a", "b", "c", "d"], ["c", "a", "b", "d"])
        #expect(change == .updated(1))
        #expect(change.animatesList)
    }

    @Test("Новый чат сверху анимируется, следующая страница снизу — нет")
    func listPaging() {
        let top = CollectionChange.between(["a", "b"], ["new", "a", "b"])
        #expect(top == .prepended(1))
        #expect(top.animatesList)
        let page = CollectionChange.between(ids(1...50), ids(1...100))
        #expect(page == .appended(50))
        #expect(!page.animatesList)
    }

    @Test("Смена папки и другой чат не анимируются")
    func reload() {
        #expect(CollectionChange.between(["a", "b"], ["c", "d"]) == .reload)
        let folder = CollectionChange.between(ids(1...30), ["3", "7"])
        #expect(folder == .removed(28))
        #expect(!folder.animatesList)
        #expect(!CollectionChange.reload.animatesTranscript)
    }

    @Test("Больше десяти изменений за раз — без анимации")
    func limit() {
        #expect(CollectionChange.between(ids(1...5), ids(1...15)) == .appended(10))
        #expect(CollectionChange.appended(10).animatesTranscript)
        #expect(!CollectionChange.appended(11).animatesTranscript)
    }

    @Test("Повтор id не роняет подсчёт")
    func duplicates() {
        let change = CollectionChange.between(["a", "a", "b"], ["b", "a"])
        #expect(change != .none)
    }
}

@Suite("Список чатов: что анимируется")
@MainActor
struct ChatListMotionTests {
    @Test("Маленькая пересекающаяся папка всё равно является reload")
    func folderSwitch() async {
        let (model, repository) = makeList()
        model.usesLocalFilters = true
        var group = chat("g", at: 100)
        group.type = .group
        repository.emit([chat("a", at: 300), chat("b", at: 200), group])
        #expect(await eventually { model.items.count == 3 })
        model.selectFolder("local.private")
        #expect(model.items.count == 2)
        #expect(model.itemsChange == .reload)
        model.selectFolder(ChatFolder.allId)
        #expect(model.items.count == 3)
        #expect(!model.itemsChange.animatesList)
    }

    @Test("Первый снимок без анимации, подъём чата с новым сообщением — с анимацией")
    func listChanges() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 300), chat("b", at: 200), chat("c", at: 100)])
        #expect(await eventually { model.items.count == 3 })
        #expect(model.itemsChange == .initial)
        #expect(!model.itemsChange.animatesList)
        repository.emit([chat("a", at: 300), chat("b", at: 200), chat("c", at: 400)])
        #expect(await eventually { model.items.first?.id == "c" })
        #expect(model.itemsChange == .updated(1))
        #expect(model.itemsChange.animatesList)
    }
}

@Suite("Лента: что анимируется")
@MainActor
struct TranscriptMotionTests {
    private func message(_ id: String) -> Message {
        Message(id: id, chatId: "c", authorId: "u", text: id, timestamp: .now, status: .sent)
    }

    @Test("Первая страница и старая история — сразу, новое и удалённое — плавно")
    func transcriptChanges() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        repository.emit(["3", "4"].map(message))
        #expect(await eventually { model.messages.count == 2 })
        #expect(model.messagesChange == .initial)
        repository.emit(["1", "2", "3", "4"].map(message))
        #expect(await eventually { model.messages.count == 4 })
        #expect(model.messagesChange == .prepended(2))
        #expect(!model.messagesChange.animatesTranscript)
        repository.emit(["1", "2", "3", "4", "5"].map(message))
        #expect(await eventually { model.messages.count == 5 })
        #expect(model.messagesChange.animatesTranscript)
        repository.emit(["1", "2", "4", "5"].map(message))
        #expect(await eventually { model.messages.count == 4 })
        #expect(model.messagesChange == .removed(1))
        #expect(model.messagesChange.animatesTranscript)
        model.deactivate()
    }

    @Test("Новая реакция или правка текста поднимает версию содержимого, статус — нет")
    func contentVersion() async {
        let repository = FakeMessageRepository()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: repository)
        model.activate()
        var first = message("1")
        first.status = .sending
        repository.emit([first])
        #expect(await eventually { model.messages.count == 1 })
        #expect(model.contentVersion == 0)
        first.status = .sent
        repository.emit([first])
        #expect(await eventually { model.messages.first?.status == .sent })
        #expect(model.contentVersion == 0)
        first.content.reactions = [MessageReaction(emoji: "👍", count: 1, mine: false)]
        repository.emit([first])
        #expect(await eventually { model.contentVersion == 1 })
        first.text = "исправлено"
        repository.emit([first])
        #expect(await eventually { model.contentVersion == 2 })
        model.deactivate()
    }
}
