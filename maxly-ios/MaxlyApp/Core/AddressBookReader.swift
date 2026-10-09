import Contacts
import Foundation
import MaxlyData
import MaxlyPresentation

/// Адресная книга телефона для «Имён из адресной книги»: только номера и имена, только
/// с разрешения (полного или на выбранные контакты). Читается в фоне; на сервер не уходит.
enum AddressBookReader {
    /// `nil` — разрешения нет.
    static func read() async -> [AddressBookEntry]? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || Self.isLimited(status) else { return nil }
        return await Task.detached(priority: .utility) { () -> [AddressBookEntry]? in
            let store = CNContactStore()
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.unifyResults = true
            var entries: [AddressBookEntry] = []
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    var first = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                    var last = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Записанный одной фамилией — имя для чатов всё равно нужно.
                    if first.isEmpty { (first, last) = (last, "") }
                    guard !first.isEmpty else { return }
                    for number in contact.phoneNumbers {
                        entries.append(AddressBookEntry(phone: number.value.stringValue, firstName: first, lastName: last))
                    }
                }
            } catch {
                return nil
            }
            return entries
        }.value
    }

    private static func isLimited(_ status: CNAuthorizationStatus) -> Bool {
        if #available(iOS 18.0, *) { return status == .limited }
        return false
    }

    /// Книга в ядро: заменяет прежнюю целиком.
    static func sender(core: MaxIosCore) -> @Sendable ([AddressBookEntry]) async -> Void {
        { entries in
            await core.setAddressBook(entries.map { CorePhoneContact(phone: $0.phone, firstName: $0.firstName, lastName: $0.lastName) })
        }
    }
}
