package app.orbitle.presentation.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfileLinkTest {
    @Test
    fun `server invite link wins over the own contact link`() {
        assertEquals("https://max.ru/u/abc", ProfileLink.link(" https://max.ru/u/abc ", "https://max.ru/me"))
        assertEquals("https://max.ru/me", ProfileLink.link("  ", "https://max.ru/me"))
        assertNull(ProfileLink.link(null, ""))
        assertEquals("Присоединяйся ко мне в MAX: https://max.ru/me", ProfileLink.inviteText("https://max.ru/me"))
    }

    @Test
    fun `qr code is square with a quiet zone and finder patterns`() {
        val rows = ProfileLink.qr("https://max.ru/u/abc", margin = 2)
        val size = rows.size
        assertTrue(size >= 21 + 4)
        assertTrue(rows.all { it.size == size })
        // Тихая зона по краю светлая, угол узора поиска тёмный.
        assertTrue(rows.first().none { it })
        assertTrue(rows.all { !it[0] })
        assertTrue(rows[2][2])
        assertTrue(rows[2][size - 3])
        assertTrue(rows[size - 3][2])
    }
}
