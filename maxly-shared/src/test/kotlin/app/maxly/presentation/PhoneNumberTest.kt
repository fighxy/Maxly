package app.maxly.presentation

import app.maxly.presentation.auth.PhoneCountry
import app.maxly.presentation.auth.PhoneNumber
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneNumberTest {
    @Test
    fun normalizesRussianNumbers() {
        assertEquals("+79991234567", PhoneNumber.normalized("+7 999 123-45-67"))
        assertEquals("+79991234567", PhoneNumber.normalized("89991234567"))
        assertEquals("+79991234567", PhoneNumber.normalized("9991234567"))
        assertNull(PhoneNumber.normalized("+7 999 123"))
        assertNull(PhoneNumber.normalized("+7 199 123-45-67"))
    }

    @Test
    fun normalizesInternationalNumbers() {
        assertEquals("+375291234567", PhoneNumber.normalized("+375 29 123 4567"))
        assertNull(PhoneNumber.normalized("+0123456789"))
        assertNull(PhoneNumber.normalized("+1234"))
    }

    @Test
    fun formatsAsTyped() {
        assertEquals("+7 9", PhoneNumber.formatted("9"))
        assertEquals("+7 999 123-45-67", PhoneNumber.formatted("89991234567"))
        assertEquals("+375291", PhoneNumber.formatted("+375291"))
        assertEquals("+", PhoneNumber.formatted("+"))
        assertEquals("", PhoneNumber.formatted(""))
    }

    @Test
    fun deletingSeparatorRemovesDigit() {
        assertEquals("+7 999 12", PhoneNumber.edit("+7 999 123", "+7 999 12"))
        assertEquals("+7 999", PhoneNumber.edit("+7 999 1", "+7 999 "))
        assertEquals("+7", PhoneNumber.edit("+7 9", "+7 "))
        assertEquals("+7 999", PhoneNumber.edit("+7 999 1", "+7 9991"))
        assertEquals("", PhoneNumber.edit("+7", "+"))
    }

    @Test
    fun displaysNormalized() {
        assertEquals("+7 999 123-45-67", PhoneNumber.display("+79991234567"))
        assertEquals("+375291234567", PhoneNumber.display("+375291234567"))
    }

    @Test
    fun countries() {
        assertEquals(PhoneCountry.russia, PhoneCountry.all.first())
        assertEquals("Россия", PhoneCountry.preferred("7")?.name)
        assertEquals("375", PhoneCountry.longestCode("375291234567"))
        assertEquals("1", PhoneCountry.longestCode("12025550123"))
        assertTrue(PhoneCountry.isComplete("375"))
        assertFalse(PhoneCountry.isComplete("37"))
        assertEquals("29 123 4567", PhoneCountry.preferred("375")?.format("291234567"))
        assertEquals("29 1", PhoneCountry.preferred("375")?.format("291"))
        assertEquals("🇷🇺", PhoneCountry.russia.flag)
        assertEquals(listOf("Беларусь"), PhoneCountry.search("бел").map { it.name })
        assertTrue(PhoneCountry.search("+375").any { it.id == "BY" })
        assertEquals("Южная Корея", PhoneCountry.search("корея").single().name)
        assertEquals(PhoneCountry.all.size, PhoneCountry.search("").size)
    }
}
