import Foundation
import Testing
@testable import OrbitlePresentation

private actor BookSink {
    private(set) var sent: [[AddressBookEntry]] = []
    func take(_ entries: [AddressBookEntry]) { sent.append(entries) }
}

@MainActor
@Suite("Имена из адресной книги")
struct AddressBookNamesSyncTests {
    private func defaults() -> UserDefaults {
        let name = "book-\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    @Test("Включено по умолчанию: книга без пустых записей уходит в ядро, на сервер — ничего")
    func sendsBook() async {
        let sink = BookSink()
        let book = [
            AddressBookEntry(phone: "8 913 123-45-67", firstName: "Мама"),
            AddressBookEntry(phone: "", firstName: "Без номера"),
            AddressBookEntry(phone: "+7 900 000-00-00", firstName: " "),
        ]
        let sync = AddressBookNamesSync(defaults: defaults(), read: { book }, send: { await sink.take($0) })
        #expect(sync.isEnabled)
        #expect(!AddressBookNamesSync.uploadsToServer)
        await sync.refresh()
        #expect(await sink.sent == [[AddressBookEntry(phone: "8 913 123-45-67", firstName: "Мама")]])
        #expect(sync.sentCount == 1)
    }

    @Test("Выключили — ядро получает пустую книгу, настройка запоминается")
    func disable() async {
        let sink = BookSink()
        let store = defaults()
        let sync = AddressBookNamesSync(defaults: store, read: { [AddressBookEntry(phone: "1234567", firstName: "Аня")] }, send: { await sink.take($0) })
        await sync.setEnabled(false)
        #expect(await sink.sent == [[]])
        #expect(store.bool(forKey: AddressBookNamesSync.settingKey) == false)
        let again = AddressBookNamesSync(defaults: store, read: { nil }, send: { _ in })
        #expect(!again.isEnabled)
    }

    @Test("Нет разрешения — пустая книга")
    func noAccess() async {
        let sink = BookSink()
        let sync = AddressBookNamesSync(defaults: defaults(), read: { nil }, send: { await sink.take($0) })
        await sync.refresh()
        #expect(await sink.sent == [[]])
    }
}
