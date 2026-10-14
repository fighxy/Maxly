package app.maxly.platform

import app.maxly.data.PreferenceStore
import app.maxly.domain.Chat
import java.awt.image.BufferedImage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopTrayTest {
    private class MemoryStore : PreferenceStore {
        val map = HashMap<String, String>()
        override fun get(key: String) = map[key]
        override fun put(key: String, value: String) { map[key] = value }
        override fun remove(key: String) { map.remove(key) }
    }

    @Test
    fun tooltipShowsUnread() {
        assertEquals("Maxly", TrayText.tooltip(0))
        assertEquals("Maxly — 1 непрочитанное", TrayText.tooltip(1))
        assertEquals("Maxly — 5 непрочитанных", TrayText.tooltip(5))
        assertEquals("Maxly — 11 непрочитанных", TrayText.tooltip(11))
        assertEquals("Maxly — 21 непрочитанное", TrayText.tooltip(21))
    }

    @Test
    fun settingsDefaultsAndPersistence() {
        val store = MemoryStore()
        val s = DesktopTraySettings(store)
        assertTrue(s.closeToTray.value)
        assertFalse(s.muted.value)
        s.setCloseToTray(false)
        s.setMuted(true)
        val again = DesktopTraySettings(store)
        assertFalse(again.closeToTray.value)
        assertTrue(again.muted.value)
    }

    @Test
    fun badgeDotOnlyWhenUnread() {
        val src = BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB)
        val plain = DesktopTray.render(src, 32, 32, dot = false)
        val dotted = DesktopTray.render(src, 32, 32, dot = true)
        assertEquals(0, plain.getRGB(26, 6) ushr 24)
        assertNotEquals(0, dotted.getRGB(26, 6) ushr 24)
    }

    @Test
    fun unreadSumsChats() {
        fun chat(id: String, unread: Int, marked: Boolean = false) =
            Chat(id, id, app.maxly.domain.ChatType.PRIVATE, unreadCount = unread, updatedAtMs = 0, isMarkedUnread = marked)
        assertEquals(0, TrayText.unread(emptyList()))
        assertEquals(6, TrayText.unread(listOf(chat("a", 2), chat("b", 3), chat("c", 0, marked = true), chat("d", 0))))
    }
}
