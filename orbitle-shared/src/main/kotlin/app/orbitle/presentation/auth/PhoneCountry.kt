package app.orbitle.presentation.auth

import java.text.Collator
import java.util.Locale

/** Страна для поля телефона: код, маска национальной части и флаг. */
data class PhoneCountry(
    val id: String,
    val name: String,
    val code: String,
    /** Маска национальной части: `0` — цифра, остальное — разделители. */
    val pattern: String,
    val minDigits: Int = pattern.count { it == '0' },
) {
    val maxDigits: Int get() = pattern.count { it == '0' }

    /** Флаг из региональных индикаторов. */
    val flag: String
        get() = id.uppercase().map { String(Character.toChars(0x1F1E6 + (it.code - 'A'.code))) }.joinToString("")

    /** Цифры по маске; разделитель ставится только перед следующей цифрой. */
    fun format(digits: String): String = buildString {
        var rest = digits
        var pending = ""
        for (symbol in pattern) {
            val digit = rest.firstOrNull() ?: break
            if (symbol == '0') {
                append(pending)
                pending = ""
                append(digit)
                rest = rest.drop(1)
            } else {
                pending += symbol
            }
        }
    }

    companion object {
        val russia = PhoneCountry("RU", "Россия", "7", "000 000 0000")

        val all: List<PhoneCountry> = listOf(
            russia,
            PhoneCountry("KZ", "Казахстан", "7", "000 000 0000"),
            PhoneCountry("BY", "Беларусь", "375", "00 000 0000"),
            PhoneCountry("UA", "Украина", "380", "00 000 0000"),
            PhoneCountry("UZ", "Узбекистан", "998", "00 000 0000"),
            PhoneCountry("KG", "Киргизия", "996", "000 000 000"),
            PhoneCountry("TJ", "Таджикистан", "992", "00 000 0000"),
            PhoneCountry("TM", "Туркменистан", "993", "00 000000"),
            PhoneCountry("AM", "Армения", "374", "00 000000"),
            PhoneCountry("AZ", "Азербайджан", "994", "00 000 0000"),
            PhoneCountry("GE", "Грузия", "995", "000 000 000"),
            PhoneCountry("MD", "Молдова", "373", "00 000 000"),
            PhoneCountry("MN", "Монголия", "976", "0000 0000"),
            PhoneCountry("LV", "Латвия", "371", "0000 0000"),
            PhoneCountry("LT", "Литва", "370", "000 00000"),
            PhoneCountry("EE", "Эстония", "372", "0000 0000", minDigits = 7),
            PhoneCountry("FI", "Финляндия", "358", "00 000 00000", minDigits = 6),
            PhoneCountry("US", "США", "1", "000 000 0000"),
            PhoneCountry("CA", "Канада", "1", "000 000 0000"),
            PhoneCountry("GB", "Великобритания", "44", "0000 000000"),
            PhoneCountry("DE", "Германия", "49", "0000 0000000", minDigits = 10),
            PhoneCountry("FR", "Франция", "33", "0 00 00 00 00"),
            PhoneCountry("IT", "Италия", "39", "000 000 0000", minDigits = 9),
            PhoneCountry("ES", "Испания", "34", "000 000 000"),
            PhoneCountry("PT", "Португалия", "351", "000 000 000"),
            PhoneCountry("NL", "Нидерланды", "31", "0 00000000"),
            PhoneCountry("PL", "Польша", "48", "000 000 000"),
            PhoneCountry("CZ", "Чехия", "420", "000 000 000"),
            PhoneCountry("RS", "Сербия", "381", "00 0000000", minDigits = 8),
            PhoneCountry("SE", "Швеция", "46", "00 000 00 00", minDigits = 7),
            PhoneCountry("NO", "Норвегия", "47", "000 00 000"),
            PhoneCountry("CY", "Кипр", "357", "00 000000"),
            PhoneCountry("TR", "Турция", "90", "000 000 0000"),
            PhoneCountry("IL", "Израиль", "972", "00 000 0000"),
            PhoneCountry("AE", "ОАЭ", "971", "00 000 0000"),
            PhoneCountry("EG", "Египет", "20", "00 0000 0000"),
            PhoneCountry("CN", "Китай", "86", "000 0000 0000"),
            PhoneCountry("IN", "Индия", "91", "00000 00000"),
            PhoneCountry("JP", "Япония", "81", "00 0000 0000"),
            PhoneCountry("KR", "Южная Корея", "82", "00 0000 0000", minDigits = 9),
            PhoneCountry("TH", "Таиланд", "66", "00 000 0000"),
            PhoneCountry("VN", "Вьетнам", "84", "00 000 00 00"),
            PhoneCountry("ID", "Индонезия", "62", "000 0000 00000", minDigits = 9),
            PhoneCountry("BR", "Бразилия", "55", "00 00000 0000"),
            PhoneCountry("AR", "Аргентина", "54", "00 0000 0000"),
            PhoneCountry("MX", "Мексика", "52", "00 0000 0000"),
        )

        /** Первая страна с кодом (для `7` — Россия). */
        fun preferred(code: String): PhoneCountry? = all.firstOrNull { it.code == code }

        /** Самый длинный известный код в начале цифр. */
        fun longestCode(digits: String): String? =
            (4 downTo 1).map { digits.take(it) }.firstOrNull { prefix -> prefix.length <= digits.length && all.any { it.code == prefix } }

        /** Код известен и не начало более длинного кода. */
        fun isComplete(code: String): Boolean {
            if (preferred(code) == null) return false
            return all.none { it.code.length > code.length && it.code.startsWith(code) }
        }

        /** Поиск по началу названия, слову в названии или коду. */
        fun search(query: String): List<PhoneCountry> {
            val collator = Collator.getInstance(Locale.forLanguageTag("ru-RU"))
            val sorted = all.sortedWith { a, b -> collator.compare(a.name, b.name) }
            val needle = query.trim().lowercase()
            if (needle.isEmpty()) return sorted
            val digits = needle.filter(Char::isAsciiDigit)
            return sorted.filter { country ->
                val name = country.name.lowercase()
                name.startsWith(needle) || name.contains(" " + needle) ||
                    (digits.isNotEmpty() && digits.length == needle.count { it != '+' } && country.code.startsWith(digits))
            }
        }
    }
}
