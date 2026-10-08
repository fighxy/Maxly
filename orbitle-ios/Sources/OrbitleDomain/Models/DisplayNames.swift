import Foundation

/// Номер телефона в одном виде для сравнения: `+` и цифры с кодом страны. Общие с Kotlin
/// правила — `test-fixtures/names` (раздел «Номер»).
///
/// - Пробелы (и неразрывные), дефисы и тире, скобки, точки и косая черта убираются.
/// - `+` в начале — номер уже с кодом страны. Ведущие `00` без `+` — то же, что `+`.
/// - Без `+`: 11 цифр с первой 8 — российский номер, 8 меняется на 7; ровно 10 цифр —
///   российский без кода, спереди ставится 7. Остальное остаётся как есть.
/// - Итог всегда с `+`. Меньше 7 или больше 15 цифр — не номер (`nil`): короткие и служебные
///   номера не сопоставляются. Любой другой знак внутри — тоже не номер.
public enum PhoneNormalizer {
    public static let minDigits = 7
    public static let maxDigits = 15

    /// Разделители внутри номера.
    static let separators: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "\t", "-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "(", ")", ".", "/"]

    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var plus = false
        var digits = ""
        for char in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            if char.isASCII, char.isNumber {
                digits.append(char)
            } else if char == "+", digits.isEmpty, !plus {
                plus = true
            } else if separators.contains(char) {
                continue
            } else {
                return nil
            }
        }
        if !plus, digits.hasPrefix("00") {
            digits.removeFirst(2)
            plus = true
        }
        if !plus {
            if digits.count == 11, digits.first == "8" {
                digits = "7" + digits.dropFirst()
            } else if digits.count == 10 {
                digits = "7" + digits
            }
        }
        guard (minDigits...maxDigits).contains(digits.count) else { return nil }
        return "+" + digits
    }
}

/// Имя пользователя для показа. Общие с Kotlin правила — `test-fixtures/names`:
/// адресная книга (если включена и номер совпал) > своё имя контакта (`CUSTOM`, переименован)
/// > имя, которое пользователь дал себе (`ONEME`) > первая запись `names` с именем > номер > «Участник».
public enum DisplayName {
    public static let fallback = "Участник"

    /// Запись `names` сервера: `{name, firstName, lastName, type}`.
    public struct Entry: Hashable, Sendable {
        public var name: String?
        public var firstName: String?
        public var lastName: String?
        public var type: String?

        public init(name: String? = nil, firstName: String? = nil, lastName: String? = nil, type: String? = nil) {
            self.name = name
            self.firstName = firstName
            self.lastName = lastName
            self.type = type
        }

        /// `name`, а если его нет — «Имя Фамилия» без пустых частей.
        public var fullName: String? {
            if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
            let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }

    /// Имя по правилу приоритета. [addressBookName] — уже найденное по номеру имя из книги
    /// (`nil`, если книга выключена или номер не совпал).
    public static func resolve(addressBookName: String?, names: [Entry], phone: String?) -> String {
        if let book = addressBookName?.trimmingCharacters(in: .whitespacesAndNewlines), !book.isEmpty { return book }
        if let custom = names.first(where: { $0.type?.uppercased() == "CUSTOM" && $0.fullName != nil })?.fullName { return custom }
        if let own = names.first(where: { $0.type?.uppercased() == "ONEME" && $0.fullName != nil })?.fullName { return own }
        if let first = names.lazy.compactMap(\.fullName).first { return first }
        if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            return PhoneNormalizer.normalize(phone) ?? phone
        }
        return fallback
    }
}

/// Имена из адресной книги устройства по номеру. Книга читается только на устройстве и на
/// сервер не уходит.
public struct AddressBookNames: Hashable, Sendable {
    /// Запись книги: имя и номера как их ввели.
    public struct Entry: Hashable, Sendable {
        public var name: String
        public var phones: [String]

        public init(name: String, phones: [String]) {
            self.name = name
            self.phones = phones
        }
    }

    /// Нормализованный номер → имя.
    public private(set) var names: [String: String]

    public init(names: [String: String] = [:]) {
        self.names = names
    }

    /// Номера записей нормализуются; у номера, который есть в нескольких записях, остаётся
    /// первое непустое имя по порядку книги. Записи без имени имени не дают.
    public init(entries: [Entry]) {
        var names: [String: String] = [:]
        for entry in entries {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            for phone in entry.phones {
                guard let key = PhoneNormalizer.normalize(phone), names[key] == nil else { continue }
                names[key] = name
            }
        }
        self.names = names
    }

    public var isEmpty: Bool { names.isEmpty }

    /// Имя для номера [phone] в любом виде (сервер шлёт цифры без `+`).
    public func name(forPhone phone: String?) -> String? {
        guard let phone, !phone.isEmpty else { return nil }
        let key = PhoneNormalizer.normalize(phone) ?? PhoneNormalizer.normalize("+" + phone)
        return key.flatMap { names[$0] }
    }
}
