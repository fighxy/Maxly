package app.orbitle.domain

/**
 * Запись телефонной книги устройства. [id] — ключ записи в системной книге (на Android —
 * `LOOKUP_KEY`), [phones] — номера, приведённые [PhoneNumbers.normalize], без повторов, в
 * порядке книги.
 */
data class PhoneBookEntry(
    val id: String,
    val displayName: String,
    val phones: List<String>,
)

/** Строка телефонной книги как её отдаёт система: один номер одной записи. */
data class PhoneBookRow(
    val entryId: String,
    val displayName: String?,
    /** Номер как его ввели. */
    val number: String?,
    /** Номер, уже приведённый системой (на Android — `NORMALIZED_NUMBER`); запасной вариант. */
    val systemNumber: String? = null,
)

/** Номера телефонов в одном виде: только цифры с кодом страны, без «+». */
object PhoneNumbers {
    /** Короче — служебные и короткие номера: аккаунтом они не бывают. */
    const val MIN_DIGITS = 7

    /** Длиннее номер E.164 не бывает. */
    const val MAX_DIGITS = 15

    /** Разделители внутри номера: пробелы, дефисы, скобки, точки, косая черта. */
    private const val SEPARATORS = "-‐‑‒–—().,/"

    /**
     * Цифры номера с кодом страны, как в E.164 без «+»; `null` — это не номер.
     *
     * - Пробелы, дефисы, скобки и точки убираются: `+7 (999) 123-45-67` → `79991234567`.
     * - Российский номер в любом виде — `8XXXXXXXXXX`, `+7XXXXXXXXXX`, `7XXXXXXXXXX` — один и тот же
     *   `7XXXXXXXXXX`: ведущая 8 у 11 цифр без «+» меняется на 7.
     * - Международный выход `00` без «+» — то же, что «+».
     * - Остальные коды стран остаются как есть.
     * - Добавочный и паузы набора после номера (`,`, `;`, `доб.`, `ext`) отбрасываются.
     */
    fun normalize(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        var plus = false
        val digits = StringBuilder()
        for (char in raw.trim()) {
            when {
                char in '0'..'9' -> digits.append(char)
                char == '+' && digits.isEmpty() -> plus = true
                char.isWhitespace() || (char in SEPARATORS && char != ',') -> Unit
                // Дальше пауза, добавочный или мусор: номер кончился.
                digits.isNotEmpty() -> break
                // До первой цифры — например, «tel:»: пропустить.
                else -> Unit
            }
        }
        var number = digits.toString()
        if (!plus && number.startsWith("00")) number = number.drop(2)
        else if (!plus && number.length == 11 && number[0] == '8') number = "7" + number.drop(1)
        return number.takeIf { it.length in MIN_DIGITS..MAX_DIGITS }
    }
}

/** Сборка записей телефонной книги из строк системы. */
object PhoneBook {
    /**
     * Строки одной записи — в одну запись в порядке первой строки. Номера нормализуются
     * ([PhoneNumbers.normalize], при неудаче — номер системы), повторы убираются; записи
     * без единого номера пропускаются. Имя — первое непустое, иначе первый номер с «+».
     */
    fun entries(rows: List<PhoneBookRow>): List<PhoneBookEntry> {
        val names = LinkedHashMap<String, String?>()
        val phones = HashMap<String, LinkedHashSet<String>>()
        for (row in rows) {
            val id = row.entryId.takeIf { it.isNotBlank() } ?: continue
            val name = row.displayName?.trim()?.takeIf { it.isNotEmpty() }
            if (names[id] == null) names[id] = name
            val phone = PhoneNumbers.normalize(row.number) ?: PhoneNumbers.normalize(row.systemNumber)
            val set = phones.getOrPut(id) { LinkedHashSet() }
            if (phone != null) set += phone
        }
        return names.mapNotNull { (id, name) ->
            val numbers = phones[id].orEmpty().toList()
            if (numbers.isEmpty()) return@mapNotNull null
            PhoneBookEntry(id, name ?: "+${numbers.first()}", numbers)
        }
    }
}
