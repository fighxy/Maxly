package app.orbitle.data

import com.max.core.api.MaxUser
import com.max.core.api.UserName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Имя и видимость контакта так, как их разбирает Komet. */
class ContactListTest {
    @Test
    fun customNameBeatsTheProfileName() {
        val (first, last) = CoreContactRepository.visibleName(
            listOf(
                UserName(name = "Анна Официальная", firstName = "Анна", lastName = "Официальная", type = "ONEME"),
                UserName(name = null, firstName = "Мама", lastName = null, type = "CUSTOM"),
            ),
        )
        assertEquals("Мама", first)
        assertEquals("", last)
    }

    @Test
    fun nameFieldFillsAnEmptyFirstAndLast() {
        val (first, last) = CoreContactRepository.visibleName(
            listOf(UserName(name = "Мама", firstName = " ", lastName = "", type = "ONEME")),
        )
        assertEquals("Мама", first)
        assertEquals("", last)
    }

    @Test
    fun deletedAccountStaysOutOfTheList() {
        assertFalse(CoreContactRepository.isListed(user(accountStatus = 2)))
        assertTrue(CoreContactRepository.isListed(user(accountStatus = 0)))
        assertTrue(CoreContactRepository.isListed(user(accountStatus = null)))
    }

    @Test
    fun optionsMarkBotOfficialAndService() {
        val contact = CoreContactRepository.contact(
            user(options = listOf("BOT", "OFFICIAL", "SERVICE_ACCOUNT")),
            com.max.core.state.MaxState(),
        )
        assertTrue(contact.isBot)
        assertTrue(contact.isOfficial)
        assertTrue(contact.isServiceAccount)
        assertEquals("Анна", contact.displayName)
    }

    private fun user(accountStatus: Int? = 0, options: List<String> = emptyList()): MaxUser = MaxUser(
        id = 7L,
        names = listOf(UserName(name = null, firstName = "Анна", lastName = null, type = "ONEME")),
        phone = 7900L,
        accountStatus = accountStatus,
        status = null,
        description = null,
        link = null,
        baseUrl = null,
        photoId = null,
        updateTime = null,
        options = options,
        raw = emptyMap<String, Any?>(),
    )
}
