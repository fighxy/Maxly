package app.maxly.presentation.notifications

import app.maxly.domain.ChatType
import app.maxly.domain.IncomingMessageNotice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MessageNotificationRulesTest {
    private fun notice(
        type: ChatType = ChatType.PRIVATE,
        title: String = "Аня",
        author: String = "Аня",
        text: String = "Привет",
        media: String = "",
        muted: Boolean = false,
    ) = IncomingMessageNotice("1", "2", title, type, author, text, media, muted, 0)

    @Test
    fun hiddenOnScreenWhenDisabledAndMuted() {
        assertNull(MessageNotificationRules.content(notice(), appActive = true, enabled = true))
        assertNull(MessageNotificationRules.content(notice(), appActive = false, enabled = false))
        assertNull(MessageNotificationRules.content(notice(muted = true), appActive = false, enabled = true))
    }

    @Test
    fun privateGroupAndChannel() {
        assertEquals(
            MessageNotificationRules.Content("Аня", null, "Привет"),
            MessageNotificationRules.content(notice(), appActive = false, enabled = true),
        )
        assertEquals(
            MessageNotificationRules.Content("Дача", "Петя", "Фото"),
            MessageNotificationRules.content(notice(ChatType.GROUP, "Дача", "Петя", " ", "Фото"), appActive = false, enabled = true),
        )
        assertEquals(
            MessageNotificationRules.Content("Чат", null, "Сообщение"),
            MessageNotificationRules.content(notice(ChatType.CHANNEL, "", "Новости", ""), appActive = false, enabled = true),
        )
        // Личный чат без названия — по автору, длинный текст обрезается.
        val long = "а".repeat(400)
        val content = MessageNotificationRules.content(notice(title = "", author = "Петя", text = long), appActive = false, enabled = true)!!
        assertEquals("Петя", content.title)
        assertEquals(MessageNotificationRules.BODY_LIMIT, content.body.length)
    }
}
