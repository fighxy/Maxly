package app.orbitle.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PhoneNumbersTest {
    private fun n(raw: String?) = PhoneNumbers.normalize(raw)

    @Test
    fun russianNumbersInEveryFormAreTheSame() {
        for (raw in listOf(
            "89991234567",
            "+79991234567",
            "79991234567",
            "8 (999) 123-45-67",
            "+7 (999) 123-45-67",
            "+7 999 123 45 67",
            "7-999-123-45-67",
            "8.999.123.45.67",
            " +7\u00A0999\u00A0123\u201145\u201167 ",
        )) {
            assertEquals(raw, "79991234567", n(raw))
        }
        // Городской с кодом города — тоже.
        assertEquals("74951234567", n("8 (495) 123-45-67"))
    }

    @Test
    fun otherCountryCodesStayAsGiven() {
        assertEquals("442079460958", n("+44 20 7946 0958"))
        assertEquals("380501234567", n("+380 (50) 123-45-67"))
        assertEquals("77011234567", n("+7 701 123 4567"))
        // «+8…» — чужой код, не российская восьмёрка.
        assertEquals("88001234567", n("+8 800 123 45 67"))
        // Международный выход 00 — то же, что «+».
        assertEquals("4930123456", n("0049 30 123456"))
        assertEquals("442079460958", n("00 44 20 7946 0958"))
    }

    @Test
    fun withoutPlusOnlyElevenDigitsWithEightAreRussian() {
        // 10 и 12 цифр с восьмёркой — не трогаются.
        assertEquals("8991234567", n("8991234567"))
        assertEquals("899912345678", n("899912345678"))
        // Местный номер без кода страны остаётся как есть.
        assertEquals("1234567", n("123-45-67"))
    }

    @Test
    fun extensionsAndPausesAreDropped() {
        assertEquals("74951234567", n("+7 495 123-45-67, 123"))
        assertEquals("74951234567", n("+7 495 123-45-67;890"))
        assertEquals("74951234567", n("+7 495 123-45-67 доб. 12"))
        assertEquals("442079460958", n("+44 20 7946 0958 ext 5"))
        assertEquals("79991234567", n("tel:+79991234567"))
    }

    @Test
    fun notANumber() {
        assertNull(n(null))
        assertNull(n(""))
        assertNull(n("   "))
        assertNull(n("нет номера"))
        // Короткие и служебные.
        assertNull(n("112"))
        assertNull(n("*100#"))
        assertNull(n("900"))
        // Длиннее E.164.
        assertNull(n("+1234567890123456"))
    }
}

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
                PhoneBookEntry("a", "Анна", listOf("79991234567", "74950000000")),
                PhoneBookEntry("b", "Борис", listOf("442079460958")),
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
            ),
        )
        assertEquals(
            listOf(
                PhoneBookEntry("a", "+79991234567", listOf("79991234567")),
                // Имя пришло в следующей строке той же записи.
                PhoneBookEntry("b", "Борис", listOf("79997654321")),
            ),
            entries,
        )
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
}
