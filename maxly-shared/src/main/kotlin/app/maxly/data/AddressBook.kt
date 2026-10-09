package app.maxly.data

import app.maxly.domain.PhoneBookEntry

/**
 * Телефонная книга устройства, только чтение. Разрешение спрашивает экран; без него
 * [entries] бросает исключение системы.
 */
interface AddressBook {
    /** На устройстве есть телефонная книга. Нет (десктоп) — вход в неё не показывается. */
    val isAvailable: Boolean

    /** Все записи с номерами ([app.maxly.domain.PhoneBook.entries]). */
    suspend fun entries(): List<PhoneBookEntry>
}

/**
 * Куда отдаётся прочитанная книга: ядру, для имён людей из книги. Каждый вызов заменяет книгу
 * целиком; пустой список — книги нет (разрешение отозвали). На сервер ничего не уходит.
 */
fun interface AddressBookSink {
    fun publish(entries: List<PhoneBookEntry>)
}

/** Книга в ядро ([MaxClient.setAddressBook]): номера как в книге, записи без имени не нужны. */
class CoreAddressBookSink(private val client: com.maxly.shared.MaxClient) : AddressBookSink {
    override fun publish(entries: List<PhoneBookEntry>) = client.setAddressBook(contacts(entries))

    companion object {
        fun contacts(entries: List<PhoneBookEntry>): List<com.maxly.core.api.PhoneContact> = entries.flatMap { entry ->
            val first = entry.firstName.trim()
            if (first.isEmpty()) emptyList()
            else entry.rawPhones.map { com.maxly.core.api.PhoneContact(it, first, entry.lastName?.trim()?.takeIf(String::isNotEmpty)) }
        }
    }
}
