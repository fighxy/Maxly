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
    fun coreTextsWithoutNames() {
        val expected = mapOf(
            "new" to "Чат создан",
            "botStarted" to "Бот запущен",
            "hello" to "Контакт теперь в MAX",
            "add" to "Добавлены участники",
            "remove" to "Удалены участники",
            "leave" to "Участник покинул(а) чат",
            "joinByLink" to "Участник вступил(а) в чат по ссылке",
            "title" to "Название чата изменено",
            "icon" to "Фото чата изменено",
            "system" to ServiceMessages.GENERIC,
            "pin" to "Сообщение закреплено",
            "unpin" to "Закрепление снято",
            "present" to ServiceMessages.GENERIC,
            "" to ServiceMessages.GENERIC,
            null to ServiceMessages.GENERIC,
        )
        for ((event, text) in expected) {
            assertEquals("$event", text, ServiceMessages.text(message(control(event))))
        }
        assertEquals("Создан чат «Дача»", ServiceMessages.text(message(control("new", "title" to "Дача"))))
    }

    @Test
    fun mineAndNamesFromTheClient() {
        val names = mapOf(42L to "Анна", 7L to "Борис", 8L to "Вера")
        fun text(control: Map<String, Any?>, sender: Long = 42L) =
            ServiceMessages.text(message(control, sender = sender), 1L) { names[it] }
        assertEquals("Анна добавил(а) Борис и Вера", text(control("add", "userIds" to listOf(7L, 8L))))
        assertEquals("Вы добавили Борис", text(control("add", "userIds" to listOf(7L)), sender = 1L))
        assertEquals("Анна удалил(а) вас", text(control("remove", "userId" to 1L)))
        assertEquals("Вы покинули чат", text(control("leave"), sender = 1L))
        assertEquals("Вы изменили название на «Дача 2027»", text(control("title", "title" to "Дача 2027"), sender = 1L))
        assertEquals("Вы запустили бота", text(control("botStarted"), sender = 1L))
        assertEquals("Анна создал(а) чат «Дача»", text(control("new", "title" to "Дача")))
        assertEquals("Вера теперь в MAX", text(control("hello", "userId" to 8L)))
        assertEquals("Анна теперь в MAX", text(control("new", "chatType" to "DIALOG")))
        assertEquals("Вы теперь в MAX", text(control("hello", "userId" to 1L)))
        assertEquals("Вы теперь в MAX", text(control("new", "chatType" to "DIALOG"), sender = 1L))
        assertEquals("Контакт теперь в MAX", text(control("new", "chatType" to "DIALOG"), sender = 99L))
        assertEquals("Контакт теперь в MAX", ServiceMessages.text(message(control("new", "chatType" to "DIALOG"), sender = 0L)))
    }

    @Test
    fun messageTextWhenTheCoreHasNone() {
        assertEquals("Текст сервера", ServiceMessages.text(message(control("system"), text = "  Текст сервера ")))
        assertEquals("Текст сервера", ServiceMessages.text(message(control("widget"), text = "Текст сервера")))
        // Известное событие пишет ядро.
        assertEquals("Контакт теперь в MAX", ServiceMessages.text(message(control("hello"), text = "Текст сервера")))
    }

    @Test
    fun controlMessageShowsViaCoreFallback() {
        assertEquals("Пётр добавлен", ServiceMessages.text(message(control("add", "shortMessage" to "Пётр добавлен", "message" to "Иван добавил Петра"))))
        assertEquals("Иван добавил Петра", ServiceMessages.text(message(control("add", "message" to "Иван добавил Петра"))))
        // Текст сервера во вложении (ядро) важнее текста сообщения.
        assertEquals("коротко", ServiceMessages.text(message(control("add", "shortMessage" to "коротко"), text = "снаружи")))
    }

    @Test
    fun lowercaseTypeKeyIsService() {
        val msg = message(mapOf("type" to "control", "event" to "leave"))
        assertTrue(ServiceMessages.isService(msg))
        assertEquals("Участник покинул(а) чат", ServiceMessages.text(msg))
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
