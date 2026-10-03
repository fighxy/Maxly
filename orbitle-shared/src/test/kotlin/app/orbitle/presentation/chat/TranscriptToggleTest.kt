package app.orbitle.presentation.chat

import app.orbitle.domain.Chat
import app.orbitle.domain.SavedMessagesWelcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptToggleTest {
    @Test
    fun descriptionFollowsTheState() {
        assertEquals("Показать расшифровку", TranscriptToggle.description(open = false))
        assertEquals("Скрыть расшифровку", TranscriptToggle.description(open = true))
    }

    @Test
    fun backgroundIsStrongerWhenOpen() {
        assertEquals(0.14f, TranscriptToggle.backgroundAlpha(open = false), 0f)
        assertEquals(0.3f, TranscriptToggle.backgroundAlpha(open = true), 0f)
    }

    @Test
    fun letterIsCyrillic() {
        assertEquals("\u0422", TranscriptToggle.LETTER)
    }

    @Test
    fun welcomeKeyMatchesOnlyInSavedMessages() {
        assertTrue(SavedMessagesWelcome.isKey("welcome.saved.dialog.message"))
        assertTrue(SavedMessagesWelcome.isKey("\n welcome.saved.dialog.message \t"))
        assertFalse(SavedMessagesWelcome.isKey("welcome.saved.dialog.message!"))
        assertFalse(SavedMessagesWelcome.isKey(null))
        assertTrue(SavedMessagesWelcome.matches(Chat.SAVED_MESSAGES_ID, "welcome.saved.dialog.message"))
        assertFalse(SavedMessagesWelcome.matches("42", "welcome.saved.dialog.message"))
    }
}
