package app.orbitle.data

import app.orbitle.domain.PhoneBookEntry

/**
 * Телефонная книга устройства, только чтение. Разрешение спрашивает экран; без него
 * [entries] бросает исключение системы.
 */
interface AddressBook {
    /** На устройстве есть телефонная книга. Нет (десктоп) — вход в неё не показывается. */
    val isAvailable: Boolean

    /** Все записи с номерами ([app.orbitle.domain.PhoneBook.entries]). */
    suspend fun entries(): List<PhoneBookEntry>
}
