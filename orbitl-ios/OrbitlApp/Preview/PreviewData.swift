#if DEBUG
import SwiftUI
import OrbitlDomain
import OrbitlPresentation

/// Примерные данные для превью Xcode: так вкладки видны целиком, пока ядро
/// не отдаёт настоящие контакты и звонки.
struct PreviewContacts: ContactRepository {
    var capabilities: ContactCapabilities { [.list, .presence, .add] }

    func contacts() -> AsyncStream<[Contact]> {
        let now = Date()
        let list = [
            Contact(id: "11", firstName: "Иван", presence: .recently),
            Contact(id: "12", firstName: "Анна", lastName: "Смирнова", presence: .online),
            Contact(id: "13", firstName: "Михаил", presence: .lastSeen(now.addingTimeInterval(-3 * 3600))),
            Contact(id: "14", firstName: "Сергей", lastName: "Орлов", presence: .lastSeen(now.addingTimeInterval(-26 * 3600))),
            Contact(id: "15", firstName: "Вера", presence: .withinWeek),
            Contact(id: "16", firstName: "Alex", presence: .longAgo),
        ]
        return AsyncStream { continuation in
            continuation.yield(list)
            continuation.finish()
        }
    }

    func addContact(phone: String, firstName: String, lastName: String) async throws(OrbitlError) -> Contact {
        Contact(id: "99", firstName: firstName, lastName: lastName, phone: phone)
    }
}

struct PreviewCalls: CallHistoryRepository {
    var capabilities: CallCapabilities { [.history, .delete] }

    func calls() -> AsyncStream<[CallRecord]> {
        let day: TimeInterval = 86_400
        let now = Date()
        func call(_ id: String, _ peer: String, _ title: String, _ direction: CallRecord.Direction, _ outcome: CallRecord.Outcome, _ ago: TimeInterval, group: Bool = false) -> CallRecord {
            CallRecord(id: id, peerId: peer, title: title, isGroup: group, direction: direction, outcome: outcome, date: now.addingTimeInterval(-ago))
        }
        let list = [
            call("1", "11", "Иван", .outgoing, .answered, 1 * day),
            call("2", "g1", "", .outgoing, .cancelled, 4 * day, group: true),
            call("3", "g2", "", .outgoing, .answered, 14 * day, group: true),
            call("4", "11", "Иван", .incoming, .answered, 15 * day),
            call("5", "11", "Иван", .incoming, .answered, 15 * day + 600),
            call("6", "11", "Иван", .incoming, .missed, 16 * day),
        ]
        return AsyncStream { continuation in
            continuation.yield(list)
            continuation.finish()
        }
    }

    func delete(ids: [String]) async throws(OrbitlError) {}
}

#Preview("Контакты") {
    NavigationStack {
        ContactsView(viewModel: ContactsViewModel(contacts: PreviewContacts(), currentUserId: "1")) { _ in }
    }
}

#Preview("Звонки") {
    NavigationStack {
        CallsView(viewModel: CallsViewModel(calls: PreviewCalls())) { _ in }
    }
}

#Preview("Контакты недоступны") {
    NavigationStack {
        ContactsView(viewModel: ContactsViewModel(contacts: UnavailablePreviewContacts(), currentUserId: "1")) { _ in }
    }
}

private struct UnavailablePreviewContacts: ContactRepository {
    var capabilities: ContactCapabilities { [] }
    func contacts() -> AsyncStream<[Contact]> { AsyncStream { $0.finish() } }
}
#endif
