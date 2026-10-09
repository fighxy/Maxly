import Foundation
import Observation
import OrbitleDomain

/// Запись адресной книги телефона: номер как в книге (ядро приводит его само) и имя.
public struct AddressBookEntry: Hashable, Sendable {
    public var phone: String
    public var firstName: String
    public var lastName: String

    public init(phone: String, firstName: String, lastName: String = "") {
        self.phone = phone
        self.firstName = firstName
        self.lastName = lastName
    }
}

/// «Имена из адресной книги»: люди в чатах подписаны так, как они записаны в телефоне.
///
/// Книга читается только с разрешения и только при включённой настройке, уходит в ядро
/// целиком (оно сопоставляет номера и выбирает имя по общему правилу, test-fixtures/names)
/// и остаётся на устройстве: на сервер не отправляется ничего. Выключили настройку — ядро
/// получает пустую книгу и возвращается к именам Max.
@MainActor
@Observable
public final class AddressBookNamesSync {
    /// Отправка книги на сервер (`SYNC` 21) выключена и в этой версии не включается.
    public static let uploadsToServer = false
    public static let settingKey = "addressBookNames"

    public private(set) var isEnabled: Bool
    /// Сколько записей с номером ушло в ядро в последний раз.
    public private(set) var sentCount = 0
    @ObservationIgnored private let defaults: UserDefaults
    /// Книга телефона; `nil` — нет разрешения.
    @ObservationIgnored private let read: @Sendable () async -> [AddressBookEntry]?
    /// Передать книгу ядру (заменяет прежнюю целиком).
    @ObservationIgnored private let send: @Sendable ([AddressBookEntry]) async -> Void
    @ObservationIgnored private var generation = 0

    public init(
        defaults: UserDefaults = .standard,
        read: @escaping @Sendable () async -> [AddressBookEntry]?,
        send: @escaping @Sendable ([AddressBookEntry]) async -> Void
    ) {
        self.defaults = defaults
        self.read = read
        self.send = send
        // Включено, пока не выключили: имена остаются на устройстве.
        isEnabled = defaults.object(forKey: Self.settingKey) as? Bool ?? true
    }

    public func setEnabled(_ value: Bool) async {
        guard value != isEnabled else { return }
        isEnabled = value
        defaults.set(value, forKey: Self.settingKey)
        await refresh()
    }

    /// Прочитать книгу заново и передать ядру: после входа, после изменения книги
    /// (`CNContactStoreDidChange`) и после возврата в приложение (разрешение могли сменить).
    public func refresh() async {
        generation += 1
        let current = generation
        guard isEnabled else {
            sentCount = 0
            await send([])
            return
        }
        let book = await read() ?? []
        // Пока читали, настройку могли выключить или начать новое чтение.
        guard current == generation, isEnabled else { return }
        let entries = book.filter {
            !$0.phone.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.firstName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        sentCount = entries.count
        await send(entries)
    }
}
