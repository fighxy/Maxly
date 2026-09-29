import Foundation

/// Номер телефона на экране входа: нормализация для ядра и маска при вводе.
///
/// Основной случай — российские номера: `+7`, `8` или десять цифр без префикса
/// становятся `+7XXXXXXXXXX`. Номер с другим кодом страны после `+` принимается
/// как международный (8–15 цифр) без маски.
public enum PhoneNumber {
    /// Первые цифры национального номера, которые принимаются после `+7`:
    /// 3, 4, 8 — стационарные и бесплатные, 9 — мобильные, 7 — Казахстан.
    static let nationalLeads: Set<Character> = ["3", "4", "7", "8", "9"]

    /// Номер в формате E.164 (`+79991234567`) или `nil`, если номер неполный или неверный.
    public static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(trimmed.filter(\.isASCIIDigit))
        if trimmed.hasPrefix("+"), !digits.hasPrefix("7") {
            guard (8...15).contains(digits.count), digits.first != "0" else { return nil }
            return "+" + digits
        }
        guard let national = russianNational(digits), national.count == 10 else { return nil }
        guard let lead = national.first, nationalLeads.contains(lead) else { return nil }
        return "+7" + national
    }

    /// Маска для поля ввода: `+7 999 123-45-67`, по мере набора.
    public static func formatted(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(trimmed.filter(\.isASCIIDigit))
        if trimmed.hasPrefix("+"), !digits.isEmpty, !digits.hasPrefix("7") {
            return "+" + digits.prefix(15)
        }
        if digits.isEmpty {
            return trimmed.hasPrefix("+") ? "+" : ""
        }
        let national = String((russianNational(digits) ?? digits).prefix(10))
        return mask(national)
    }

    /// Правка поля: новая маска с учётом стёртого разделителя.
    ///
    /// Если пользователь стёр пробел или дефис, цифры не изменились и маска вернула бы
    /// тот же текст. Тогда стирается последняя цифра, как ожидает человек.
    public static func edit(from old: String, to new: String) -> String {
        let oldDigits = old.filter(\.isASCIIDigit)
        let newDigits = new.filter(\.isASCIIDigit)
        if new.count < old.count, newDigits == oldDigits, !newDigits.isEmpty {
            if newDigits.count == 1, old.hasPrefix("+7") { return "" }
            return formatted(String(new.hasPrefix("+") ? "+" : "") + newDigits.dropLast())
        }
        if new == "+", old.hasPrefix("+7") {
            // Стёрли семёрку после плюса: поле пустеет, а не остаётся с одиноким плюсом.
            return ""
        }
        return formatted(new)
    }

    /// Нормализованный номер для текста «код отправлен на…».
    public static func display(_ normalized: String) -> String {
        guard normalized.hasPrefix("+7") else { return normalized }
        let digits = String(normalized.dropFirst(2).filter(\.isASCIIDigit))
        return mask(digits)
    }

    /// Национальная часть российского номера: без `7` или `8` в начале одиннадцати цифр.
    private static func russianNational(_ digits: String) -> String? {
        guard let first = digits.first else { return "" }
        if first == "7" || first == "8" {
            return String(digits.dropFirst())
        }
        return digits
    }

    private static func mask(_ national: String) -> String {
        var result = "+7"
        for (index, digit) in national.prefix(10).enumerated() {
            switch index {
            case 0, 3: result.append(" ")
            case 6, 8: result.append("-")
            default: break
            }
            result.append(digit)
        }
        return result
    }
}

extension Character {
    /// Только цифры 0–9: арабские и прочие цифры Unicode номер не принимает.
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
