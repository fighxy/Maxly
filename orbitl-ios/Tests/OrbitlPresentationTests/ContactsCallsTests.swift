import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlPresentation

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

    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitlError) -> Contact {
        guard capabilities.contains(.add) else { throw .invalidRequest }
        lock.withLock { added.append(phone) }
        return Contact(id: "99", firstName: firstName, lastName: lastName, phone: phone)
    }
}

final class FakeCallSource: CallHistoryRepository, @unchecked Sendable {
    let capabilities: CallCapabilities
    private let lock = NSLock()
    private let initial: [CallRecord]
    private(set) var deleted: [[String]] = []
    var failDelete = false

    init(_ calls: [CallRecord] = [], capabilities: CallCapabilities = [.history, .delete]) {
        self.initial = calls
        self.capabilities = capabilities
    }

    func calls() -> AsyncStream<[CallRecord]> {
        AsyncStream { continuation in continuation.yield(initial) }
    }

    func delete(ids: [String]) async throws(OrbitlError) {
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
    func make(_ calls: [CallRecord], capabilities: CallCapabilities = [.history, .delete]) -> (CallsViewModel, FakeCallSource) {
        let source = FakeCallSource(calls, capabilities: capabilities)
        let model = CallsViewModel(calls: source, calendar: moscowCalendar(), now: { referenceNow })
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
        #expect(model.missedCount == 2)
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
