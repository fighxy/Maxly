package app.maxly.data

import com.max.core.api.MaxMessage
import com.max.core.api.MaxUser
import com.max.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FoundMessagesTest {
    private val me = 1L

    private fun message(id: Long, text: String, time: Long, sender: Long = 2L) =
        MaxMessage.from(mapOf("id" to id, "text" to text, "time" to time, "sender" to sender, "type" to "USER"))!!

    private val anna = MaxUser.from(mapOf("id" to 2L, "names" to listOf(mapOf("name" to "Анна"))))!!

    @Test
    fun mergesServerWithLoadedWithoutRepeatsNewestFirst() {
        val state = MaxState(
            me = me,
            users = mapOf(2L to anna),
            messages = mapOf(
                10L to listOf(message(1, "Привет всем", 3_000), message(2, "пока", 4_000)),
                11L to listOf(message(5, "и тебе привет", 5_000, sender = me)),
            ),
        )
        val server = listOf(
            10L to message(1, "Привет всем", 0),
            12L to message(7, "привет из архива", 1_000, sender = 3),
            0L to message(8, "привет без чата", 9_000),
            13L to message(9, "   ", 9_000),
        )
        val found = CoreChatRepository.foundMessages(" привет ", server, state)
        assertEquals(listOf("11" to "5", "10" to "1", "12" to "7"), found.map { it.chatId to it.messageId })
        // У загруженной копии точное время, а не 0 из ответа сервера.
        assertEquals(3_000L, found[1].timeMs)
        assertTrue(found[0].isOutgoing)
        assertEquals("Анна", found[1].senderName)
        assertFalse(found[1].isOutgoing)
        assertNull(found[2].senderName)
    }

    @Test
    fun blankQueryFindsNothing() {
        val state = MaxState(messages = mapOf(10L to listOf(message(1, "текст", 1))))
        assertTrue(CoreChatRepository.foundMessages("  ", emptyList(), state).isEmpty())
    }
}
