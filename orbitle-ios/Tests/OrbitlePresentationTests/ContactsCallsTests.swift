import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

final class FakeContactSource: ContactRepository, @unchecked Sendable {
    let capabilities: ContactCapabilities
    private let lock = NSLock()
    private var continuation: AsyncStream<[Contact]>.Continuation?
    private var initial: [Contact]
    private(set) var added: [String] = []

    init(_ contacts: [Contact] = [], capabilities: ContactCapabilities = [.list, .presence]) {
        self.initial = contacts
        self.capabilities = capabilities
    }

    func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.yield(initial)
        }
    }

    func send(_ contacts: [Contact]) {
        lock.withLock { continuation }?.yield(contacts)
    }

    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitleError) -> Contact {
        guard capabilities.contains(.add) else { throw .invalidRequest }
        lock.withLock { added.append(phone) }
        return Contact(id: "99", firstName: firstName, lastName: lastName, phone: phone)
    }
}

final class FakeCallSource: CallHistoryRepository, @unchecked Sendable {
    let capabilities: CallCapabilities
    private let lock = NSLock()
    private let initial: [CallRecord]
    private var continuation: AsyncStream<[CallRecord]>.Continuation?
    private(set) var deleted: [[String]] = []
    private(set) var refreshes = 0
    /// Что вернёт следующая загрузка с сервера (`refresh`). `nil`: прежний список.
    var server: [CallRecord]?
    var failDelete = false

    init(_ calls: [CallRecord] = [], capabilities: CallCapabilities = [.history, .delete]) {
        self.initial = calls
        self.capabilities = capabilities
    }

    func calls() -> AsyncStream<[CallRecord]> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.yield(initial)
        }
    }

    /// Новый список, как после загрузки с сервера или пуша.
    func send(_ calls: [CallRecord]) {
        lock.withLock { continuation }?.yield(calls)
    }

    func refresh() async {
        let next: [CallRecord]? = lock.withLock {
            refreshes += 1
            return server
        }
        if let next { send(next) }
    }

    func delete(ids: [String]) async throws(OrbitleError) {
        if failDelete { throw .networkUnavailable }
        lock.withLock { deleted.append(ids) }
    }
}

private func moscowCalendar() -> Calendar {
    ChatListFormatter.defaultCalendar(timeZone: TimeZone(identifier: "Europe/Moscow")!)
}

/// 29 сентября 2026, 15:00 по Москве.
private let referenceNow = Date(timeIntervalSince1970: 1_790_683_200)

private func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
    let calendar = moscowCalendar()
    let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: referenceNow))!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

@Suite("Контакты")
@MainActor
struct ContactsViewModelTests {
    func make(_ contacts: [Contact], capabilities: ContactCapabilities = [.list, .presence]) -> (ContactsViewModel, FakeContactSource) {
        let source = FakeContactSource(contacts, capabilities: capabilities)
        let model = ContactsViewModel(
            contacts: source,
            currentUserId: "1",
            formatter: ContactsFormatter(calendar: moscowCalendar()),
            now: { referenceNow }
        )
        model.activate()
        return (model, source)
    }

    @Test("Разделы по буквам: кириллица, латиница, затем «#»; «Ё» вместе с «Е»")
    func sections() async {
        let (model, _) = make([
            Contact(id: "2", firstName: "Иван"),
            Contact(id: "3", firstName: "anna"),
            Contact(id: "4", firstName: "Ёлка"),
            Contact(id: "5", firstName: "Андрей"),
            Contact(id: "6", firstName: "42"),
            Contact(id: "7", firstName: "Émile"),
            Contact(id: "1", firstName: "Я сам"),
        ])
        _ = await eventually { model.state == .ready }
        let filled = model.sections.filter { !$0.rows.isEmpty }
        #expect(filled.map(\.id) == ["А", "Е", "И", "A", "E", "#"])
        #expect(filled.first?.rows.map(\.title) == ["Андрей"])
        #expect(model.sections.map(\.id) == ContactsViewModel.indexTitles)
        #expect(!model.sections.flatMap(\.rows).contains { $0.id == "1" })
        #expect(model.count == 6)
    }

    @Test("Буква без контактов ведёт к следующему непустому разделу")
    func indexJump() async {
        let (model, _) = make([Contact(id: "2", firstName: "Иван"), Contact(id: "3", firstName: "Zoe")])
        _ = await eventually { model.state == .ready }
        #expect(model.sectionId(forIndexTitle: "И") == "И")
        #expect(model.sectionId(forIndexTitle: "А") == "И")
        #expect(model.sectionId(forIndexTitle: "К") == "Z")
        #expect(model.sectionId(forIndexTitle: "#") == "Z")
    }

    @Test("Статус: в сети, недавно, время последнего визита")
    func presence() async {
        let (model, _) = make([
            Contact(id: "2", firstName: "Анна", presence: .online),
            Contact(id: "3", firstName: "Борис", presence: .recently),
            Contact(id: "4", firstName: "Вера", presence: .lastSeen(date(daysAgo: 0, hour: 12, minute: 40))),
            Contact(id: "5", firstName: "Глеб", presence: .lastSeen(date(daysAgo: 1, hour: 9, minute: 5))),
            Contact(id: "6", firstName: "Дина", presence: .lastSeen(date(daysAgo: 20, hour: 9))),
            Contact(id: "7", firstName: "Егор", presence: .lastSeen(referenceNow.addingTimeInterval(-5 * 60))),
        ])
        _ = await eventually { model.state == .ready }
        let rows = model.sections.flatMap(\.rows)
        #expect(rows.map(\.status) == [
            "В сети", "Был(а) недавно", "Был(а) в 12:40", "Был(а) вчера в 09:05", "Был(а) 9 сен", "Был(а) 5 минут назад",
        ])
        #expect(rows.first?.isOnline == true)
        #expect(rows.dropFirst().allSatisfy { !$0.isOnline })
    }

    @Test("Неизвестный статус — пустая строка, а не «недавно»; время из будущего — «только что»")
    func unknownAndFuturePresence() async {
        let (model, _) = make([
            Contact(id: "2", firstName: "Анна", presence: .unknown),
            Contact(id: "3", firstName: "Борис", presence: .lastSeen(referenceNow.addingTimeInterval(3 * 3600))),
            Contact(id: "4", firstName: "Вера", presence: .lastSeen(referenceNow.addingTimeInterval(-30))),
        ])
        _ = await eventually { model.state == .ready }
        #expect(model.sections.flatMap(\.rows).map(\.status) == ["", "Был(а) только что", "Был(а) только что"])
        let formatter = ContactsFormatter(calendar: moscowCalendar())
        #expect(formatter.status(.unknown, now: referenceNow).isEmpty)
        #expect(formatter.status(.recently, now: referenceNow) == "Был(а) недавно")
    }

    @Test("«N минут назад» пересчитывается со временем, а не застывает на загрузке")
    func relativeTimeTicks() async {
        final class Clock { var date = referenceNow }
        let clock = Clock()
        let source = FakeContactSource([
            Contact(id: "2", firstName: "Анна", presence: .lastSeen(referenceNow.addingTimeInterval(-5 * 60))),
        ])
        let model = ContactsViewModel(
            contacts: source, currentUserId: "1",
            formatter: ContactsFormatter(calendar: moscowCalendar()),
            now: { clock.date }
        )
        model.activate()
        _ = await eventually { model.state == .ready }
        #expect(model.sections.flatMap(\.rows).first?.status == "Был(а) 5 минут назад")
        clock.date = referenceNow.addingTimeInterval(2 * 60)
        model.refreshTimes()
        #expect(model.sections.flatMap(\.rows).first?.status == "Был(а) 7 минут назад")
    }

    @Test("Поиск по имени и телефону, без разделов")
    func search() async {
        let (model, _) = make([
            Contact(id: "2", firstName: "Иван", lastName: "Петров", phone: "+79991234567"),
            Contact(id: "3", firstName: "Пётр"),
            Contact(id: "4", firstName: "Анна"),
        ])
        _ = await eventually { model.state == .ready }
        model.query = "пет"
        #expect(model.isFiltering)
        #expect(model.searchResults.map(\.title) == ["Пётр", "Иван Петров"])
        model.query = "1234"
        #expect(model.searchResults.map(\.title) == ["Иван Петров"])
        model.isSearching = true
        model.isSearching = false
        #expect(model.query.isEmpty)
        #expect(model.searchResults.isEmpty)
    }

    @Test("Список обновляется из потока; пустой список — пустое состояние")
    func updates() async {
        let (model, source) = make([])
        _ = await eventually { model.state == .empty }
        source.send([Contact(id: "2", firstName: "Иван")])
        _ = await eventually { model.state == .ready }
        #expect(model.sections.first { $0.id == "И" }?.rows.count == 1)
    }

    @Test("Без поддержки источника раздел недоступен, добавить нельзя")
    func unavailable() async {
        let (model, _) = make([], capabilities: [])
        #expect(model.state == .unavailable)
        #expect(!model.canAdd)
        #expect(await model.addContact(phone: "+79990000000", firstName: "А", lastName: "") == false)
        #expect(model.errorMessage != nil)
    }

    @Test("Добавление контакта и id диалога")
    func addAndChat() async {
        let (model, source) = make([], capabilities: [.list, .add])
        #expect(model.canAdd)
        #expect(await model.addContact(phone: "+79990000000", firstName: "Иван", lastName: ""))
        #expect(source.added == ["+79990000000"])
        #expect(model.chatId(forContact: "3") == "2")
        #expect(model.chatId(forContact: "x") == nil)
    }
}

@Suite("Звонки")
@MainActor
struct CallsViewModelTests {
    func make(
        _ calls: [CallRecord],
        capabilities: CallCapabilities = [.history, .delete],
        marks: InMemoryCallHistoryMarks? = nil
    ) -> (CallsViewModel, FakeCallSource) {
        let source = FakeCallSource(calls, capabilities: capabilities)
        // По умолчанию вкладку смотрели месяц назад.
        let marks = marks ?? InMemoryCallHistoryMarks(lastSeen: date(daysAgo: 30, hour: 0))
        let model = CallsViewModel(calls: source, marks: marks, calendar: moscowCalendar(), now: { referenceNow })
        model.activate()
        return (model, source)
    }

    func call(_ id: String, _ peer: String, _ title: String, _ direction: CallRecord.Direction, _ outcome: CallRecord.Outcome, _ date: Date, group: Bool = false) -> CallRecord {
        CallRecord(id: id, peerId: peer, title: title, isGroup: group, chatId: "c\(peer)", direction: direction, outcome: outcome, date: date)
    }

    var sample: [CallRecord] {
        [
            call("1", "10", "Иван", .outgoing, .answered, date(daysAgo: 1, hour: 10)),
            call("2", "20", "", .outgoing, .cancelled, date(daysAgo: 4, hour: 10), group: true),
            call("3", "10", "Иван", .incoming, .answered, date(daysAgo: 15, hour: 12)),
            call("4", "10", "Иван", .incoming, .answered, date(daysAgo: 15, hour: 11)),
            call("5", "10", "Иван", .incoming, .missed, date(daysAgo: 0, hour: 14, minute: 32)),
            call("6", "10", "Иван", .incoming, .missed, date(daysAgo: 400, hour: 9)),
        ]
    }

    @Test("Группировка подряд идущих звонков, статусы, иконки и даты")
    func grouping() async {
        let (model, _) = make(sample)
        _ = await eventually { model.state == .ready }
        #expect(model.rows.map(\.title) == ["Иван", "Иван", "Групповой звонок", "Иван (2)", "Иван"])
        #expect(model.rows.map(\.status) == ["Пропущенный", "Исходящий", "Отменённый", "Входящий", "Пропущенный"])
        #expect(model.rows.map(\.dateText) == ["14:32", "28 сен", "25 сен", "14 сен", "25.08.2025"])
        #expect(model.rows.map(\.directionSymbol) == [
            "phone.arrow.down.left", "phone.arrow.up.right", "phone.down", "phone.arrow.down.left", "phone.arrow.down.left",
        ])
        #expect(model.rows[0].isMissed)
        #expect(!model.rows[1].isMissed)
        #expect(model.rows[3].callIds == ["3", "4"])
        #expect(model.rows[2].isGroup)
        // Пропущенный 400 дней назад старше последнего просмотра, в бейдж идёт только свежий.
        #expect(model.unseenMissedCount == 1)
    }

    @Test("«Пропущенные» оставляют только пропущенные входящие")
    func missedFilter() async {
        let (model, _) = make(sample)
        _ = await eventually { model.state == .ready }
        model.filter = .missed
        #expect(model.rows.map(\.id) == ["5", "6"])
        #expect(model.rows.allSatisfy { $0.isMissed })
    }

    @Test("Удаление убирает строку сразу и уходит на сервер; ошибка возвращает её")
    func delete() async {
        let (model, source) = make(sample)
        _ = await eventually { model.state == .ready }
        let grouped = model.rows[3]
        await model.delete(grouped)
        #expect(!model.rows.contains { $0.id == grouped.id })
        #expect(source.deleted == [["3", "4"]])

        source.failDelete = true
        let first = model.rows[0]
        await model.delete(first)
        #expect(model.rows.first?.id == first.id)
        #expect(model.errorMessage != nil)
    }

    @Test("Без удаления на сервере строка скрывается только на устройстве")
    func localDelete() async {
        let (model, source) = make(sample, capabilities: [.history])
        _ = await eventually { model.state == .ready }
        await model.delete(model.rows[0])
        #expect(model.rows.count == 4)
        #expect(source.deleted.isEmpty)
    }

    @Test("Бейдж: удаление и скрытие на устройстве сразу его уменьшают, скрытые не возвращаются")
    func badgeAfterDelete() async {
        let marks = InMemoryCallHistoryMarks(lastSeen: date(daysAgo: 30, hour: 0))
        let missed = [
            call("m1", "10", "Иван", .incoming, .missed, date(daysAgo: 0, hour: 9)),
            call("m2", "20", "Анна", .incoming, .missed, date(daysAgo: 1, hour: 9)),
            call("m3", "30", "Олег", .incoming, .missed, date(daysAgo: 2, hour: 9)),
        ]
        let (model, source) = make(missed, capabilities: [.history], marks: marks)
        _ = await eventually { model.unseenMissedCount == 3 }
        #expect(model.unseenMissedCount == 3)
        for row in model.rows { await model.delete(row) }
        #expect(model.rows.isEmpty)
        #expect(model.unseenMissedCount == 0)
        #expect(marks.hiddenIds == ["m1", "m2", "m3"])

        // Перезапуск: сервер по-прежнему отдаёт эти звонки, но они скрыты.
        model.deactivate()
        let (again, _) = make(missed, capabilities: [.history], marks: marks)
        _ = await eventually { again.state == .empty }
        #expect(again.state == .empty)
        #expect(again.unseenMissedCount == 0)
        _ = source
    }

    @Test("Бейдж: звонки, удалённые на другом устройстве, пропадают после загрузки истории")
    func badgeAfterRemoteDelete() async {
        let first = call("m1", "10", "Иван", .incoming, .missed, date(daysAgo: 0, hour: 9))
        let second = call("m2", "20", "Анна", .incoming, .missed, date(daysAgo: 1, hour: 9))
        let (model, source) = make([first, second])
        _ = await eventually { model.unseenMissedCount == 2 }
        source.send([second])
        _ = await eventually { model.unseenMissedCount == 1 }
        #expect(model.unseenMissedCount == 1)
        #expect(model.rows.map(\.id) == ["m2"])

        // Скрытый на устройстве звонок, которого больше нет на сервере, из отметок убирается.
        let marks = InMemoryCallHistoryMarks(lastSeen: date(daysAgo: 30, hour: 0), hiddenIds: ["m1", "gone"])
        let (other, otherSource) = make([first, second], capabilities: [.history], marks: marks)
        _ = await eventually { other.state == .ready }
        #expect(marks.hiddenIds == ["m1"])
        otherSource.send([])
        _ = await eventually { other.state == .empty }
        // Пустой ответ может быть ошибкой загрузки: скрытые остаются.
        #expect(marks.hiddenIds == ["m1"])
    }

    @Test("Бейдж считает только непросмотренные: открытая вкладка их просматривает и грузит историю")
    func badgeUnseen() async {
        let marks = InMemoryCallHistoryMarks(lastSeen: date(daysAgo: 1, hour: 12))
        let old = call("m1", "10", "Иван", .incoming, .missed, date(daysAgo: 2, hour: 9))
        let fresh = call("m2", "20", "Анна", .incoming, .missed, date(daysAgo: 0, hour: 9))
        let (model, source) = make([old, fresh], marks: marks)
        _ = await eventually { model.state == .ready }
        #expect(model.unseenMissedCount == 1)

        let newer = call("m3", "30", "Олег", .incoming, .missed, date(daysAgo: 0, hour: 10))
        source.server = [newer, fresh, old]
        await model.appeared()
        #expect(source.refreshes == 1)
        _ = await eventually { model.rows.count == 3 }
        // Пришёл, пока вкладка открыта: сразу просмотрен.
        #expect(model.unseenMissedCount == 0)
        #expect(marks.lastSeen == newer.date)

        model.disappeared()
        let latest = call("m4", "40", "Мария", .incoming, .missed, date(daysAgo: 0, hour: 11))
        source.send([latest, newer, fresh, old])
        _ = await eventually { model.unseenMissedCount == 1 }
        #expect(model.unseenMissedCount == 1)
        // Отвеченные и исходящие в бейдж не идут.
        source.send([call("a1", "50", "Пётр", .incoming, .answered, date(daysAgo: 0, hour: 12)), latest])
        _ = await eventually { model.rows.count == 2 }
        #expect(model.unseenMissedCount == 1)

        await model.refresh()
        #expect(source.refreshes == 2)
    }

    @Test("Первый запуск у аккаунта: прежняя история просмотрена, бейдж пуст")
    func badgeFirstRun() async {
        let marks = InMemoryCallHistoryMarks()
        let (model, _) = make([call("m1", "10", "Иван", .incoming, .missed, date(daysAgo: 0, hour: 9))], marks: marks)
        _ = await eventually { model.state == .ready }
        #expect(marks.lastSeen == referenceNow)
        #expect(model.unseenMissedCount == 0)
    }

    @Test("Ошибка удаления на сервере возвращает звонок и в бейдж, и в отметки")
    func badgeDeleteFailure() async {
        let marks = InMemoryCallHistoryMarks(lastSeen: date(daysAgo: 30, hour: 0))
        let (model, source) = make([call("m1", "10", "Иван", .incoming, .missed, date(daysAgo: 0, hour: 9))], marks: marks)
        _ = await eventually { model.unseenMissedCount == 1 }
        source.failDelete = true
        await model.delete(model.rows[0])
        #expect(model.unseenMissedCount == 1)
        #expect(marks.hiddenIds.isEmpty)
    }

    @Test("Пустая история и недоступный источник")
    func states() async {
        let (empty, _) = make([])
        _ = await eventually { empty.state == .empty }
        #expect(empty.state == .empty)
        let (unavailable, _) = make([], capabilities: [])
        #expect(unavailable.state == .unavailable)
        #expect(!unavailable.canCreateCall)
        #expect(!unavailable.canJoin)
        await unavailable.createCallLink()
        #expect(unavailable.createdLink == nil)
        #expect(unavailable.errorMessage != nil)
    }
}
