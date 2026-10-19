package app.maxly.data

import com.maxly.core.api.MaxMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServiceMessagesTest {
    private fun message(control: Map<String, Any?>?, text: String = "", sender: Long? = 42L, extra: Map<String, Any?> = emptyMap()) =
        MaxMessage.from(
            mapOf("id" to 7L, "chatId" to 555L, "sender" to sender, "text" to text, "time" to 1L, "type" to "USER") +
                (if (control != null) mapOf("attaches" to listOf(mapOf("_type" to "PHOTO"), control)) else emptyMap()) + extra,
            555L,
        )!!

    private fun control(event: String?, vararg fields: Pair<String, Any?>) = mapOf("_type" to "CONTROL", "event" to event) + fields

    @Test
    fun knownEventsUseCoreText() {
        assertEquals("Создан чат «Дача»", ServiceMessages.text(message(control("new", "title" to "Дача"))))
        assertEquals("Чат создан", ServiceMessages.text(message(control("new"))))
        assertEquals("Бот запущен", ServiceMessages.text(message(control("botStarted"))))
    }

    @Test
    fun unknownEventsShowGenericPill() {
        for (event in listOf("hello", "system", "add", "remove", "leave", "title", "icon", "joinByLink", "pin", "", null)) {
            assertEquals("$event", ServiceMessages.GENERIC, ServiceMessages.text(message(control(event))))
        }
    }

    @Test
    fun serverTextWins() {
        assertEquals("Текст сервера", ServiceMessages.text(message(control("hello"), text = "  Текст сервера ")))
        assertEquals("Текст сервера", ServiceMessages.text(message(control("new", "title" to "Дача"), text = "Текст сервера")))
    }

    @Test
    fun plainMessageIsNotService() {
        val plain = message(null, text = "привет")
        assertFalse(ServiceMessages.isService(plain))
        assertNull(ServiceMessages.text(plain))
        assertNull(ServiceMessages.preview(plain))
        assertTrue(ServiceMessages.isService(message(control("hello"))))
    }

    @Test
    fun previewIsOneLine() {
        assertEquals("раз два", ServiceMessages.preview(message(control("x"), text = "раз\n два")))
    }

    @Test
    fun debugLineHidesIds() {
        val msg = message(
            control("hello", "userId" to 1001L, "userIds" to listOf(1002L, 1001L), "chatId" to 555L, "message" to "Кто-то теперь здесь"),
            sender = 1001L,
        )
        val line = ServiceMessages.debugLine(ServiceMessages.control(msg)!!, msg)
        assertTrue(line, line.startsWith("unknown CONTROL {"))
        assertTrue(line, "\"event\":\"hello\"" in line)
        assertTrue(line, "\"userId\":\"#user1\"" in line)
        assertTrue(line, "\"userIds\":[\"#user2\",\"#user1\"]" in line)
        assertTrue(line, "Кто-то теперь здесь" in line)
        assertTrue(line, "\"messageType\":\"USER\"" in line)
        assertFalse(line, "555" in line)
        assertFalse(line, "1001" in line)
        assertFalse(line, "1002" in line)
    }

    @Test
    fun debugLogOnlyWhenEnabledAndOncePerShape() {
        val lines = mutableListOf<String>()
        ServiceMessages.debugLog = null
        ServiceMessages.text(message(control("shapeA")))
        assertTrue(lines.isEmpty())
        try {
            ServiceMessages.debugLog = { lines += it }
            ServiceMessages.text(message(control("shapeB", "title" to "x")))
            ServiceMessages.text(message(control("shapeB", "title" to "y")))
            ServiceMessages.text(message(control("new")))
            ServiceMessages.text(message(control("shapeC"), text = "есть текст"))
            assertEquals(1, lines.size)
            assertTrue("shapeB" in lines.single())
        } finally {
            ServiceMessages.debugLog = null
        }
    }
}
