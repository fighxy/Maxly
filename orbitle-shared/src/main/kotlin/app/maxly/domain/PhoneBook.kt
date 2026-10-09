package app.maxly.domain

import com.maxly.core.api.PhoneNumbers

/**
 * Запись телефонной книги устройства. [id] — ключ записи в системной книге (на Android —
 * `LOOKUP_KEY`). [phones] — номера, приведённые ядром ([PhoneNumbers.normalize]: `+` и цифры),
 * без повторов, в порядке книги; [rawPhones] — те же номера, как их записали в книге (ядру они
 * уходят как есть, приводит оно само). [firstName] пуст, если у записи нет имени.
 */
data class PhoneBookEntry(
    val id: String,
    val displayName: String,
    val phones: List<String>,
    val firstName: String = displayName,
    val lastName: String? = null,
    val rawPhones: List<String> = phones,
)

/** Строка телефонной книги как её отдаёт система: один номер одной записи. */
data class PhoneBookRow(
    val entryId: String,
    val displayName: String?,
    /** Номер как его ввели. */
    val number: String?,
    /** Номер, уже приведённый системой (на Android — `NORMALIZED_NUMBER`); запасной вариант. */
    val systemNumber: String? = null,
    /** Имя и фамилия из структурированного имени записи, если они есть. */
    val givenName: String? = null,
    val familyName: String? = null,
)

/** Сборка записей телефонной книги из строк системы. */
object PhoneBook {
    /**
     * Строки одной записи — в одну запись в порядке первой строки. Номер строки — тот из «как
     * ввели» и «как привела система», что ядро смогло привести; повторы убираются, записи без
     * единого номера пропускаются. Имя — первое непустое, иначе первый номер. Имя и фамилия —
     * из структурированного имени, а без него всё имя целиком идёт в [PhoneBookEntry.firstName].
     */
    fun entries(rows: List<PhoneBookRow>): List<PhoneBookEntry> {
        val names = LinkedHashMap<String, String?>()
        val given = HashMap<String, String>()
        val family = HashMap<String, String>()
        val phones = HashMap<String, LinkedHashMap<String, String>>()
        for (row in rows) {
            val id = row.entryId.takeIf { it.isNotBlank() } ?: continue
            val name = row.displayName?.trim()?.takeIf { it.isNotEmpty() }
            if (names[id] == null) names[id] = name
            row.givenName?.trim()?.takeIf { it.isNotEmpty() }?.let { given.putIfAbsent(id, it) }
            row.familyName?.trim()?.takeIf { it.isNotEmpty() }?.let { family.putIfAbsent(id, it) }
            val numbers = phones.getOrPut(id) { LinkedHashMap() }
            val raw = listOfNotNull(row.number, row.systemNumber).firstOrNull { PhoneNumbers.normalize(it) != null } ?: continue
            numbers.putIfAbsent(PhoneNumbers.normalize(raw)!!, raw.trim())
        }
        return names.mapNotNull { (id, name) ->
            val numbers = phones[id].orEmpty()
            if (numbers.isEmpty()) return@mapNotNull null
            val (first, last) = when {
                given[id] != null -> given.getValue(id) to family[id]
                family[id] != null -> family.getValue(id) to null
                else -> name.orEmpty() to null
            }
            PhoneBookEntry(
                id = id,
                displayName = name ?: numbers.keys.first(),
                phones = numbers.keys.toList(),
                firstName = first,
                lastName = last,
                rawPhones = numbers.values.toList(),
            )
        }
    }
}
