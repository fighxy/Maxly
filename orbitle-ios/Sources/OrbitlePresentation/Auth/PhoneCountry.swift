import Foundation

/// Страна для экрана входа: код, маска национального номера и название.
public struct PhoneCountry: Identifiable, Hashable, Sendable {
    /// Код ISO 3166-1 alpha-2.
    public let id: String
    public let name: String
    /// Телефонный код без плюса.
    public let code: String
    /// Маска национальной части: `0` — цифра, остальное — разделители.
    public let pattern: String
    /// Минимум цифр национальной части. Обычно равен длине маски.
    public let minDigits: Int

    public init(id: String, name: String, code: String, pattern: String, minDigits: Int? = nil) {
        self.id = id
        self.name = name
        self.code = code
        self.pattern = pattern
        self.minDigits = minDigits ?? pattern.filter { $0 == "0" }.count
    }

    /// Сколько цифр помещается в маску.
    public var maxDigits: Int { pattern.filter { $0 == "0" }.count }

    /// Флаг из букв региона.
    public var flag: String {
        id.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
            .map(String.init)
            .joined()
    }

    /// Цифры по маске: `9991234567` → `999 123 4567`. Лишние цифры маска не принимает.
    public func format(_ digits: String) -> String {
        var result = ""
        var rest = Substring(digits)
        var pendingSeparator = ""
        for symbol in pattern {
            guard let digit = rest.first else { break }
            if symbol == "0" {
                result += pendingSeparator
                pendingSeparator = ""
                result.append(digit)
                rest = rest.dropFirst()
            } else {
                pendingSeparator.append(symbol)
            }
        }
        return result
    }

    public static let russia = PhoneCountry(id: "RU", name: "Россия", code: "7", pattern: "000 000 0000")

    /// Страны списка выбора. Для общего кода первой идёт страна по умолчанию
    /// (Россия для `+7`, США для `+1`).
    public static let all: [PhoneCountry] = [
        russia,
        PhoneCountry(id: "KZ", name: "Казахстан", code: "7", pattern: "000 000 0000"),
        PhoneCountry(id: "BY", name: "Беларусь", code: "375", pattern: "00 000 0000"),
        PhoneCountry(id: "UA", name: "Украина", code: "380", pattern: "00 000 0000"),
        PhoneCountry(id: "UZ", name: "Узбекистан", code: "998", pattern: "00 000 0000"),
        PhoneCountry(id: "KG", name: "Киргизия", code: "996", pattern: "000 000 000"),
        PhoneCountry(id: "TJ", name: "Таджикистан", code: "992", pattern: "00 000 0000"),
        PhoneCountry(id: "TM", name: "Туркменистан", code: "993", pattern: "00 000000"),
        PhoneCountry(id: "AM", name: "Армения", code: "374", pattern: "00 000000"),
        PhoneCountry(id: "AZ", name: "Азербайджан", code: "994", pattern: "00 000 0000"),
        PhoneCountry(id: "GE", name: "Грузия", code: "995", pattern: "000 000 000"),
        PhoneCountry(id: "MD", name: "Молдова", code: "373", pattern: "00 000 000"),
        PhoneCountry(id: "MN", name: "Монголия", code: "976", pattern: "0000 0000"),
        PhoneCountry(id: "LV", name: "Латвия", code: "371", pattern: "0000 0000"),
        PhoneCountry(id: "LT", name: "Литва", code: "370", pattern: "000 00000"),
        PhoneCountry(id: "EE", name: "Эстония", code: "372", pattern: "0000 0000", minDigits: 7),
        PhoneCountry(id: "FI", name: "Финляндия", code: "358", pattern: "00 000 00000", minDigits: 6),
        PhoneCountry(id: "US", name: "США", code: "1", pattern: "000 000 0000"),
        PhoneCountry(id: "CA", name: "Канада", code: "1", pattern: "000 000 0000"),
        PhoneCountry(id: "GB", name: "Великобритания", code: "44", pattern: "0000 000000"),
        PhoneCountry(id: "DE", name: "Германия", code: "49", pattern: "0000 0000000", minDigits: 10),
        PhoneCountry(id: "FR", name: "Франция", code: "33", pattern: "0 00 00 00 00"),
        PhoneCountry(id: "IT", name: "Италия", code: "39", pattern: "000 000 0000", minDigits: 9),
        PhoneCountry(id: "ES", name: "Испания", code: "34", pattern: "000 000 000"),
        PhoneCountry(id: "PT", name: "Португалия", code: "351", pattern: "000 000 000"),
        PhoneCountry(id: "NL", name: "Нидерланды", code: "31", pattern: "0 00000000"),
        PhoneCountry(id: "PL", name: "Польша", code: "48", pattern: "000 000 000"),
        PhoneCountry(id: "CZ", name: "Чехия", code: "420", pattern: "000 000 000"),
        PhoneCountry(id: "RS", name: "Сербия", code: "381", pattern: "00 0000000", minDigits: 8),
        PhoneCountry(id: "SE", name: "Швеция", code: "46", pattern: "00 000 00 00", minDigits: 7),
        PhoneCountry(id: "NO", name: "Норвегия", code: "47", pattern: "000 00 000"),
        PhoneCountry(id: "CY", name: "Кипр", code: "357", pattern: "00 000000"),
        PhoneCountry(id: "TR", name: "Турция", code: "90", pattern: "000 000 0000"),
        PhoneCountry(id: "IL", name: "Израиль", code: "972", pattern: "00 000 0000"),
        PhoneCountry(id: "AE", name: "ОАЭ", code: "971", pattern: "00 000 0000"),
        PhoneCountry(id: "EG", name: "Египет", code: "20", pattern: "00 0000 0000"),
        PhoneCountry(id: "CN", name: "Китай", code: "86", pattern: "000 0000 0000"),
        PhoneCountry(id: "IN", name: "Индия", code: "91", pattern: "00000 00000"),
        PhoneCountry(id: "JP", name: "Япония", code: "81", pattern: "00 0000 0000"),
        PhoneCountry(id: "KR", name: "Южная Корея", code: "82", pattern: "00 0000 0000", minDigits: 9),
        PhoneCountry(id: "TH", name: "Таиланд", code: "66", pattern: "00 000 0000"),
        PhoneCountry(id: "VN", name: "Вьетнам", code: "84", pattern: "00 000 00 00"),
        PhoneCountry(id: "ID", name: "Индонезия", code: "62", pattern: "000 0000 00000", minDigits: 9),
        PhoneCountry(id: "BR", name: "Бразилия", code: "55", pattern: "00 00000 0000"),
        PhoneCountry(id: "AR", name: "Аргентина", code: "54", pattern: "00 0000 0000"),
        PhoneCountry(id: "MX", name: "Мексика", code: "52", pattern: "00 0000 0000"),
    ]

    /// Страна по умолчанию для кода или `nil`, если код неизвестен.
    public static func preferred(forCode code: String) -> PhoneCountry? {
        all.first { $0.code == code }
    }

    /// Самый длинный известный код в начале цифр номера.
    public static func longestCode(in digits: String) -> String? {
        (1...4).reversed()
            .map { String(digits.prefix($0)) }
            .first { prefix in prefix.count <= digits.count && all.contains { $0.code == prefix } }
    }

    /// Код набран полностью: длиннее известного кода с тем же началом нет.
    public static func isComplete(code: String) -> Bool {
        guard preferred(forCode: code) != nil else { return false }
        return !all.contains { $0.code.count > code.count && $0.code.hasPrefix(code) }
    }

    /// Список для выбора: по названию по алфавиту, поиск по названию или коду.
    public static func search(_ query: String) -> [PhoneCountry] {
        let sorted = all.sorted { $0.name.compare($1.name, locale: Locale(identifier: "ru_RU")) == .orderedAscending }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sorted }
        let digits = needle.filter(\.isASCIIDigit)
        return sorted.filter { country in
            country.name.lowercased().hasPrefix(needle)
                || country.name.lowercased().contains(" " + needle)
                || (!digits.isEmpty && digits.count == needle.filter { $0 != "+" }.count && country.code.hasPrefix(digits))
        }
    }
}
