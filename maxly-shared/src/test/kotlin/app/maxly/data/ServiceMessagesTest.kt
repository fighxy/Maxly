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
    fun ownTextsWithoutNames() {
        val expected = mapOf(
            "hello" to "Контакт теперь в MAX",
            "add" to "Участник вступил(а) в чат",
            "remove" to "Участник удалил(а) участника",
            "leave" to "Участник покинул(а) чат",
            "joinByLink" to "Участник вступил(а) в чат по ссылке",
            "title" to "Участник изменил(а) название чата",
            "icon" to "Участник изменил(а) фото чата",
            "system" to ServiceMessages.GENERIC,
            "present" to ServiceMessages.GENERIC,
            "" to ServiceMessages.GENERIC,
            null to ServiceMessages.GENERIC,
        )
        for ((event, text) in expected) {
            assertEquals("$event", text, ServiceMessages.text(message(control(event))))
        }
    }

    @Test
    fun mineAndNamesFromTheClient() {
        val names = mapOf("42" to "Анна", "7" to "Борис", "8" to "Вера")
        fun text(control: Map<String, Any?>, sender: Long = 42L, viewer: String = "1") =
            ServiceMessages.text(message(control, sender = sender), viewer, { names[it] })
        assertEquals("Анна добавил(а) Борис и Вера", text(control("add", "userIds" to listOf(7L, 8L))))
        assertEquals("Вы добавили Борис", text(control("add", "userIds" to listOf(7L)), sender = 1L))
        assertEquals("Анна удалил(а) вас", text(control("remove", "userId" to 1L)))
        assertEquals("Вы покинули чат", text(control("leave"), sender = 1L))
        assertEquals("Вы изменили название на «Дача 2027»", text(control("title", "title" to "Дача 2027"), sender = 1L))
        assertEquals("Вы запустили бота", ServiceMessages.text(ServiceMessages.notice(listOf(control("botStarted")))!!, "1", null, "1"))
        assertEquals("Вера теперь в MAX", text(control("hello", "userId" to 8L)))
        assertEquals("Анна теперь в MAX", text(control("new", "chatType" to "DIALOG")))
        assertEquals("Вы теперь в MAX", text(control("hello", "userId" to 1L)))
    }

    @Test
    fun messageTextOnlyForSystemAndUnknownEvents() {
        assertEquals("Текст сервера", ServiceMessages.text(message(control("system"), text = "  Текст сервера ")))
        assertEquals("Текст сервера", ServiceMessages.text(message(control("widget"), text = "Текст сервера")))
        // Известное событие пишется своим текстом или текстом ядра, как на iOS.
        assertEquals("Контакт теперь в MAX", ServiceMessages.text(message(control("hello"), text = "Текст сервера")))
        assertEquals("Создан чат «Дача»", ServiceMessages.text(message(control("new", "title" to "Дача"), text = "Текст сервера")))
    }

    @Test
    fun controlMessageShowsViaCoreFallback() {
        assertEquals("Пётр добавлен", ServiceMessages.text(message(control("add", "shortMessage" to "Пётр добавлен", "message" to "Иван добавил Петра"))))
        assertEquals("Иван добавил Петра", ServiceMessages.text(message(control("add", "message" to "Иван добавил Петра"))))
        // Текст сервера во вложении важнее текста сообщения (текст ядра идёт первым).
        assertEquals("коротко", ServiceMessages.text(message(control("add", "shortMessage" to "коротко"), text = "снаружи")))
    }

    @Test
    fun lowercaseTypeKeyIsService() {
        val msg = message(mapOf("type" to "control", "event" to "leave"))
        assertTrue(ServiceMessages.isService(msg))
        assertEquals("Участник покинул(а) чат", ServiceMessages.text(msg))
    }

    @Test
    fun pinKeepsItsOwnRow() {
        val pin = message(control("pin", "pinnedMessage" to mapOf("id" to 77L, "text" to "Сбор в 10")))
        assertTrue(ServiceMessages.isService(pin))
        assertNull(ServiceMessages.notice(pin.attaches))
        assertEquals("Закреплено: Сбор в 10", ServiceMessages.text(pin))
        assertEquals("Закрепление снято", ServiceMessages.text(message(control("unpin"))))
        assertEquals("Закрепление снято", ServiceMessages.text(message(control("pin"))))
    }

    @Test
    fun notificationsLikeIos() {
        assertTrue(ServiceMessages.notifies(message(null, text = "привет")))
        assertTrue(ServiceMessages.notifies(message(control("hello"))))
        assertTrue(ServiceMessages.notifies(message(control("new", "chatType" to "DIALOG"))))
        assertTrue(ServiceMessages.notifies(message(control("pin", "pinnedMessage" to mapOf("id" to 77L, "text" to "x")))))
        for (event in listOf("new", "add", "remove", "leave", "joinByLink", "title", "icon", "botStarted", "system", "present", null)) {
            assertFalse("$event", ServiceMessages.notifies(message(control(event))))
        }
        assertFalse(ServiceMessages.notifies(message(control("new", "chatType" to "CHAT"))))
    }

    @Test
    fun participantCounts() {
        assertEquals("участника", ServiceMessages.participants(21))
        assertEquals("участников", ServiceMessages.participants(11))
        assertEquals("участников", ServiceMessages.participants(5))
        assertEquals("участника", ServiceMessages.participants(3))
    }

    @Test
    fun typelessMessageStillMaps() {
        val raw = mapOf("id" to 7L, "chatId" to 555L, "text" to "", "time" to 1L, "attaches" to listOf(control("add", "shortMessage" to "ок")))
        val msg = MaxMessage.from(raw, 555L)!!
        assertEquals("", msg.type)
        assertEquals("ок", ServiceMessages.text(msg))
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
            ServiceMessages.text(message(control("shapeB", "photoToken" to "x")))
            ServiceMessages.text(message(control("shapeB", "photoToken" to "y")))
            ServiceMessages.text(message(control("new")))
            ServiceMessages.text(message(control("shapeC"), text = "есть текст"))
            assertEquals(1, lines.size)
            assertTrue("shapeB" in lines.single())
        } finally {
            ServiceMessages.debugLog = null
        }
    }
}
