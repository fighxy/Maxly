package app.maxly.domain

import app.maxly.data.CoreAddressBookSink
import com.maxly.core.api.PhoneContact
import org.junit.Assert.assertEquals
import org.junit.Test

/** Нормализацию номеров проверяет ядро; здесь — сборка записей поверх неё. */
class PhoneBookTest {
    @Test
    fun rowsOfOneEntryMergeAndRepeatsCollapse() {
        val entries = PhoneBook.entries(
            listOf(
                PhoneBookRow("a", "Анна", "8 999 123-45-67"),
                PhoneBookRow("b", "Борис", "+44 20 7946 0958"),
                PhoneBookRow("a", "Анна", "+7 999 123 45 67"),
                PhoneBookRow("a", "Анна", "+7 495 000-00-00"),
            ),
        )
        assertEquals(
            listOf(
                PhoneBookEntry("a", "Анна", listOf("+79991234567", "+74950000000"), rawPhones = listOf("8 999 123-45-67", "+7 495 000-00-00")),
                PhoneBookEntry("b", "Борис", listOf("+442079460958"), rawPhones = listOf("+44 20 7946 0958")),
            ),
            entries,
        )
    }

    @Test
    fun systemNumberIsAFallbackAndNamelessEntriesShowTheNumber() {
        val entries = PhoneBook.entries(
            listOf(
                PhoneBookRow("a", null, "мама", systemNumber = "+79991234567"),
                PhoneBookRow("b", "  ", "+7 999 765 43 21"),
                PhoneBookRow("b", "Борис", null),
                // Добавочный ядро номером не считает: остаётся номер системы.
                PhoneBookRow("c", "Офис", "+7 495 123-45-67 доб. 12", systemNumber = "+74951234567"),
            ),
        )
        assertEquals(
            listOf(
                PhoneBookEntry("a", "+79991234567", listOf("+79991234567"), firstName = "", rawPhones = listOf("+79991234567")),
                // Имя пришло в следующей строке той же записи.
                PhoneBookEntry("b", "Борис", listOf("+79997654321"), rawPhones = listOf("+7 999 765 43 21")),
                PhoneBookEntry("c", "Офис", listOf("+74951234567")),
            ),
            entries,
        )
    }

    @Test
    fun structuredNamesSplitIntoFirstAndLast() {
        val entries = PhoneBook.entries(
            listOf(
                PhoneBookRow("a", "Анна Смирнова", "+79991234567", givenName = "Анна", familyName = "Смирнова"),
                PhoneBookRow("b", "Смирнов", "+79991234568", familyName = "Смирнов"),
                PhoneBookRow("c", "Дядя Ваня", "+79991234569"),
            ),
        )
        assertEquals(listOf("Анна" to "Смирнова", "Смирнов" to null, "Дядя Ваня" to null), entries.map { it.firstName to it.lastName })
    }

    @Test
    fun entriesWithoutUsableNumbersAreSkipped() {
        val entries = PhoneBook.entries(
            listOf(
                PhoneBookRow("a", "Такси", "900"),
                PhoneBookRow("", "Без ключа", "+79991234567"),
                PhoneBookRow("c", "Пусто", null),
            ),
        )
        assertEquals(emptyList<PhoneBookEntry>(), entries)
    }

    @Test
    fun theCoreGetsRawNumbersOfNamedEntries() {
        val entries = PhoneBook.entries(
            listOf(
                PhoneBookRow("a", "Анна Смирнова", "8 999 123-45-67", givenName = "Анна", familyName = "Смирнова"),
                PhoneBookRow("a", "Анна Смирнова", "+7 495 000-00-00"),
                PhoneBookRow("b", null, "+79997654321"),
            ),
        )
        assertEquals(
            listOf(
                PhoneContact("8 999 123-45-67", "Анна", "Смирнова"),
                PhoneContact("+7 495 000-00-00", "Анна", "Смирнова"),
            ),
            CoreAddressBookSink.contacts(entries),
        )
    }
}
