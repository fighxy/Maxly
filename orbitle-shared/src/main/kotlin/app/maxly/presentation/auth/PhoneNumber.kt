package app.maxly.presentation.auth

/** Российский номер: нормализация для сервера и маска `+7 999 123-45-67` для поля. */
object PhoneNumber {
    private val nationalLeads = setOf('3', '4', '7', '8', '9')

    /** `+7XXXXXXXXXX` или международный `+…` (8–15 цифр). `null`, если номер неполный. */
    fun normalized(input: String): String? {
        val trimmed = input.trim()
        val digits = trimmed.filter(Char::isAsciiDigit)
        if (trimmed.startsWith("+") && !digits.startsWith("7")) {
            if (digits.length !in 8..15 || digits.first() == '0') return null
            return "+$digits"
        }
        val national = russianNational(digits)
        if (national.length != 10) return null
        if (national.first() !in nationalLeads) return null
        return "+7$national"
    }

    /** Маска для поля по мере набора. */
    fun formatted(input: String): String {
        val trimmed = input.trim()
        val digits = trimmed.filter(Char::isAsciiDigit)
        if (trimmed.startsWith("+") && digits.isNotEmpty() && !digits.startsWith("7")) {
            return "+" + digits.take(15)
        }
        if (digits.isEmpty()) return if (trimmed.startsWith("+")) "+" else ""
        return mask(russianNational(digits).take(10))
    }

    /** Правка поля: стёртый разделитель убирает цифру перед ним. */
    fun edit(old: String, new: String): String {
        val oldDigits = old.filter(Char::isAsciiDigit)
        val newDigits = new.filter(Char::isAsciiDigit)
        if (new.length < old.length && newDigits == oldDigits && newDigits.isNotEmpty()) {
            if (newDigits.length == 1 && old.startsWith("+7")) return ""
            return formatted((if (new.startsWith("+")) "+" else "") + newDigits.dropLast(1))
        }
        // Стёрли семёрку после плюса: поле пустеет, а не остаётся с одиноким плюсом.
        if (new == "+" && old.startsWith("+7")) return ""
        return formatted(new)
    }

    /** Нормализованный номер для текста «Мы отправили код на …». */
    fun display(normalized: String): String {
        if (!normalized.startsWith("+7")) return normalized
        return mask(normalized.drop(2).filter(Char::isAsciiDigit))
    }

    private fun russianNational(digits: String): String {
        val first = digits.firstOrNull() ?: return ""
        return if (first == '7' || first == '8') digits.drop(1) else digits
    }

    private fun mask(national: String): String = buildString {
        append("+7")
        national.take(10).forEachIndexed { index, digit ->
            when (index) {
                0, 3 -> append(' ')
                6, 8 -> append('-')
            }
            append(digit)
        }
    }
}

internal fun Char.isAsciiDigit(): Boolean = this in '0'..'9'
