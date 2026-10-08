import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@MainActor
func makeList(connection: FakeConnection? = nil) -> (ChatListViewModel, FakeChatRepository) {
    let repository = FakeChatRepository()
    let formatter = ChatListFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "UTC")!))
    // Вторник, 29 сентября 2026, 12:00 UTC.
    let model = ChatListViewModel(chats: repository, connection: connection, formatter: formatter, now: { Date(timeIntervalSince1970: 1_790_683_200) })
    model.activate()
    return (model, repository)
}

@Suite("Список чатов: состояние")
@MainActor
struct ChatListStateTests {
    @Test("До первого снимка загрузка, пустой снимок — пустой список")
    func loadingThenEmpty() async {
        let (model, repository) = makeList()
        #expect(model.content == .loading)
        repository.emit([])
        #expect(await eventually { model.content == .empty })
        #expect(model.banner == nil)
    }

    @Test("Пока идёт первое обновление, пустой кэш показывается как загрузка")
    func firstRefreshLoading() async {
        let (model, repository) = makeList()
        let gate = Gate()
        await repository.set(refreshGate: gate)
        repository.emit([])
        let refresh = Task { await model.refresh() }
        #expect(await eventually { await gate.arrivals == 1 })
        #expect(model.isRefreshing)
        #expect(model.content == .loading)
        await gate.open()
        await refresh.value
        #expect(await eventually { model.content == .empty })
    }

    @Test("Чаты сортируются по времени, при равенстве по id")
    func sorting() async {
        let (model, repository) = makeList()
        repository.emit([chat("b", at: 100), chat("c", at: 300), chat("a", at: 100)])
        #expect(await eventually { model.items.count == 3 })
        #expect(model.items.map(\.id) == ["c", "a", "b"])
        #expect(model.content == .list)
    }

    @Test("Живое обновление из репозитория меняет строки и бейджи")
    func liveUpdates() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1_790_672_700, unread: 0, preview: "Первое")])
        #expect(await eventually { model.items.first?.preview == "Первое" })
        #expect(model.items.first?.unreadBadge == nil)
        #expect(model.items.first?.time == "09:05")
        repository.emit([
            chat("b", at: 1_790_680_000, unread: 150, preview: "Новое"),
            chat("a", at: 1_790_672_700, unread: 1, preview: "Первое"),
        ])
        #expect(await eventually { model.items.first?.id == "b" })
        #expect(model.items.first?.unreadBadge == "150")
        #expect(model.items.last?.unreadBadge == "1")
        #expect(model.totalUnread == 151)
    }

    @Test("Ошибка обновления на пустом списке — экран ошибки, на непустом — строка над списком")
    func refreshErrors() async {
        let (model, repository) = makeList()
        repository.emit([])
        await repository.set(refreshError: .server(code: "500", text: nil))
        await model.refresh()
        // Снимок из потока может прийти позже ответа обновления.
        #expect(await eventually { model.content == .failed("Ошибка сервера (500). Попробуйте позже") })
        #expect(model.inlineError == nil)

        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.content == .list })
        #expect(model.inlineError == "Ошибка сервера (500). Попробуйте позже")
        model.dismissError()
        #expect(model.inlineError == nil)

        await repository.set(refreshError: nil)
        await model.refresh()
        #expect(model.error == nil)
        #expect(await repository.refreshCount == 2)
    }

    @Test("После восстановления связи список догружается, плашка говорит «Обновление…»")
    func catchUpAfterReconnect() async {
        let connection = FakeConnection()
        let (model, repository) = makeList(connection: connection)
        repository.emit([chat("a", at: 1)])
        connection.emit(.online)
        #expect(await eventually { model.connection == .online })
        await model.refresh()
        #expect(await repository.refreshCount == 1)

        connection.emit(.offline)
        #expect(await eventually { model.connection == .offline })
        let gate = Gate()
        await repository.set(refreshGate: gate)
        connection.emit(.online)
        #expect(await eventually { model.banner == "Обновление…" })
        await gate.open()
        #expect(await eventually { model.banner == nil && !model.isCatchingUp })
        #expect(await repository.refreshCount == 2)
    }

    @Test("Долгая догрузка после обрыва не задерживает новые состояния соединения")
    func catchUpDoesNotBlockConnection() async {
        let connection = FakeConnection()
        let (model, repository) = makeList(connection: connection)
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.connection == .online })
        await model.refresh()
        connection.emit(.offline)
        #expect(await eventually { model.connection == .offline })

        let gate = Gate()
        await repository.set(refreshGate: gate)
        connection.emit(.online)
        #expect(await eventually { await gate.arrivals == 1 })
        // Догрузка висит на сервере, а связь снова пропала: плашка должна это показать.
        connection.emit(.offline)
        #expect(await eventually { model.connection == .offline })
        #expect(model.banner == "Нет соединения. Показаны сохранённые чаты")
        await gate.open()
        #expect(await eventually { !model.isCatchingUp })
    }

    @Test("Отмена обновления не показывается")
    func cancelledRefresh() async {
        let (model, repository) = makeList()
        repository.emit([])
        await repository.set(refreshError: .cancelled)
        await model.refresh()
        #expect(model.error == nil)
        #expect(await eventually { model.content == .empty })
    }

    @Test("Повторное обновление во время текущего не запускается")
    func refreshOnce() async {
        let (model, repository) = makeList()
        let gate = Gate()
        await repository.set(refreshGate: gate)
        let first = Task { await model.refresh() }
        #expect(await eventually { await gate.arrivals == 1 })
        await model.refresh()
        await gate.open()
        await first.value
        #expect(await repository.refreshCount == 1)
    }
}

@Suite("Список чатов: соединение")
@MainActor
struct ChatListConnectionTests {
    @Test("Плашка идёт за состоянием соединения")
    func banner() async {
        let connection = FakeConnection(initial: .connecting)
        let (model, repository) = makeList(connection: connection)
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.content == .list && model.connection == .connecting })
        #expect(model.banner == "Подключение…")
        connection.emit(.offline)
        #expect(await eventually { model.banner == "Нет соединения. Показаны сохранённые чаты" })
        connection.emit(.online)
        #expect(await eventually { model.banner == nil })
    }

    @Test("Без сети и без кэша — отдельный экран, плашка не дублирует")
    func offlineEmpty() async {
        let connection = FakeConnection(initial: .offline)
        let (model, repository) = makeList(connection: connection)
        repository.emit([])
        #expect(await eventually { model.content == .offline })
        #expect(model.banner == nil)
    }

    @Test("Сетевая ошибка при офлайн-плашке не повторяется строкой")
    func networkErrorHidden() async {
        let connection = FakeConnection(initial: .offline)
        let (model, repository) = makeList(connection: connection)
        repository.emit([chat("a", at: 1)])
        #expect(await eventually { model.connection == .offline && model.content == .list })
        await repository.set(refreshError: .networkUnavailable)
        await model.refresh()
        #expect(model.error == .networkUnavailable)
        #expect(model.inlineError == nil)
    }

    @Test("Подключение до первого ответа сервера показывается загрузкой")
    func connectingEmpty() async {
        let connection = FakeConnection(initial: .connecting)
        let (model, repository) = makeList(connection: connection)
        repository.emit([])
        #expect(await eventually { model.connection == .connecting })
        #expect(model.content == .loading)
    }
}

@Suite("Список чатов: прочтение")
@MainActor
struct ChatListReadTests {
    @Test("Открытие чата его не читает: прочитанным его отмечает экран по увиденному")
    func openDoesNotMark() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1, unread: 3)])
        #expect(await eventually { model.items.first?.unreadBadge == "3" })
        await model.open(chatId: "a")
        #expect(model.openChatId == "a")
        #expect(model.items.first?.unreadBadge == "3")
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await repository.marked.isEmpty)
    }

    @Test("Новое сообщение в открытом чате список сам не читает")
    func liveMessageInOpenChat() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1, unread: 0), chat("b", at: 2, unread: 0)])
        #expect(await eventually { model.items.count == 2 })
        await model.open(chatId: "a")
        repository.emit([chat("a", at: 3, unread: 1), chat("b", at: 2, unread: 4)])
        #expect(await eventually { model.items.first(where: { $0.id == "a" })?.unreadBadge == "1" })
        #expect(model.items.first(where: { $0.id == "b" })?.unreadBadge == "4")
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await repository.marked.isEmpty)
    }

    @Test("Свайп «прочитано» отмечает чат сразу")
    func swipeMarks() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1, unread: 2), chat("b", at: 2, unread: 0)])
        #expect(await eventually { model.items.count == 2 })
        await model.toggleRead(chatId: "a")
        #expect(model.items.first(where: { $0.id == "a" })?.unreadBadge == nil)
        #expect(await repository.marked == ["a"])
    }

    @Test("Сетевая ошибка отметки не показывается, остальные показываются")
    func markErrors() async {
        let (model, repository) = makeList()
        repository.emit([chat("a", at: 1, unread: 1), chat("b", at: 2, unread: 1)])
        #expect(await eventually { model.items.count == 2 })
        await repository.set(markError: .networkUnavailable)
        await model.toggleRead(chatId: "a")
        #expect(model.error == nil)
        await repository.set(markError: .storageError)
        await model.toggleRead(chatId: "b")
        #expect(model.error == .storageError)
        #expect(model.inlineError == "Не удалось сохранить данные на устройстве")
    }
}
