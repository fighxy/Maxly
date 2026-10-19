package app.maxly.data

import com.maxly.core.api.MaxMessage
import com.maxly.core.media.Attachment
import com.maxly.core.media.attachments
import com.maxly.core.media.controlFallbackText
import com.maxly.core.media.isService
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Служебные сообщения: вложение `CONTROL`, его разбирает ядро ([Attachment.Control]).
 *
 * Подпись: текст самого сообщения, если сервер его прислал, иначе подпись ядра
 * ([controlFallbackText]) для известных событий, иначе [GENERIC]. Служебное сообщение без
 * текста не прячется: в ленте и в списке чатов остаётся серая строка.
 */
object ServiceMessages {

    const val GENERIC = "Служебное сообщение"

    /**
     * Отладочный журнал сырых `CONTROL` с событием без подписи ядра — чтобы снять форму
     * событий вроде «… теперь в MAX». По умолчанию выключен; включает только отладочная сборка
     * Android (`BuildConfig.DEBUG`) или десктоп с `MAXLY_DEBUG_CONTROL=1`. В строку не попадают
     * id чата и сообщения, id пользователей заменены метками.
     */
    @Volatile
    var debugLog: ((String) -> Unit)? = null

    private val logged = RecentKeys(LOGGED_SHAPES)

    fun control(message: MaxMessage): Attachment.Control? =
        message.attachments.firstNotNullOfOrNull { it as? Attachment.Control }

    fun isService(message: MaxMessage?): Boolean = message?.isService == true

    /** Подпись служебного [message]; `null`, если сообщение не служебное. */
    fun text(message: MaxMessage): String? {
        val control = control(message) ?: return null
        return text(control, message)
    }

    fun text(control: Attachment.Control, message: MaxMessage): String {
        message.text.trim().takeIf { it.isNotEmpty() }?.let { return it }
        controlFallbackText(control)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        logUnknown(control, message)
        return GENERIC
    }

    /** Строка для списка чатов: та же подпись в одну строку. */
    fun preview(message: MaxMessage): String? = text(message)?.replace(Regex("\\s+"), " ")?.trim()

    private fun logUnknown(control: Attachment.Control, message: MaxMessage) {
        val sink = debugLog ?: return
        val shape = "${control.event}|${control.raw.keys.map { it.toString() }.sorted()}"
        if (!logged.add(shape)) return
        runCatching { sink(debugLine(control, message)) }
    }

    /**
     * Строка отладочного журнала: `CONTROL` целиком (id пользователей → `#user1`, `#user2`…),
     * тип сообщения, есть ли текст и какие ключи пришли в самом сообщении.
     */
    fun debugLine(control: Attachment.Control, message: MaxMessage): String {
        val users = LinkedHashMap<Long, String>()
        fun user(id: Long) = users.getOrPut(id) { "#user${users.size + 1}" }
        message.sender?.let(::user)
        val json = JsonObject(
            mapOf(
                "event" to (control.event?.let(::JsonPrimitive) ?: JsonNull),
                "control" to redact(control.raw, ::user),
                "messageType" to JsonPrimitive(message.type),
                "sender" to (message.sender?.let { JsonPrimitive(user(it)) } ?: JsonNull),
                "hasText" to JsonPrimitive(message.text.isNotBlank()),
                "messageKeys" to JsonArray(((message.raw["message"] as? Map<*, *>) ?: message.raw).keys.map { JsonPrimitive(it.toString()) }),
            ),
        )
        return "unknown CONTROL $json"
    }

    private val USER_KEYS = setOf("userId", "userIds", "contactId", "contactIds", "sender", "owner")
    private val ID_KEYS = setOf("chatId", "id", "messageId", "cid", "chatIds")

    private fun redact(value: Any?, user: (Long) -> String, key: String? = null): JsonElement = when {
        value == null -> JsonNull
        key in ID_KEYS -> JsonPrimitive("#id")
        value is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to redact(v, user, k.toString()) })
        value is List<*> -> JsonArray(value.map { redact(it, user, key) })
        key in USER_KEYS && ChatMapping.longOf(value) != null -> JsonPrimitive(user(ChatMapping.longOf(value)!!))
        value is Boolean -> JsonPrimitive(value)
        value is Number -> JsonPrimitive(value)
        else -> JsonPrimitive(value.toString())
    }

    private const val LOGGED_SHAPES = 64
}
