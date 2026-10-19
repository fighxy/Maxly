package app.maxly.data

import com.maxly.core.api.MaxMessage
import com.maxly.core.state.MaxState
import com.maxly.core.media.Attachment
import com.maxly.core.media.attachments
import com.maxly.core.media.isService
import com.maxly.core.media.controlFallbackText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Служебные сообщения: вложение `CONTROL` (`_type` в любом регистре или `type: "control"` —
 * узнаёт ядро, [Attachment.from]).
 *
 * Текст пишет ядро ([controlFallbackText]): сначала текст сервера (`shortMessage`, `message`),
 * затем свой текст известного события — «Вы» для своих событий, имена участников из [MaxState]
 * (контакты и известные пользователи), «… теперь в MAX» для `hello` и `new` личного чата,
 * «Закреплено: …» / «Сообщение закреплено» / «Закрепление снято» для `pin` и `unpin` (текст
 * закрепа без `pinnedMessage.text` — из сообщений чата в сторе, [localText]).
 * Если ядру сказать нечего (`system`, незнакомое событие без текста сервера) — текст
 * самого сообщения, иначе [GENERIC]. Служебное сообщение без текста не прячется: в ленте и в
 * списке чатов остаётся серая строка. Сценарии — `test-fixtures/service-messages`.
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

    /** `CONTROL` сообщения в разборе ядра (`_type` в любом регистре или `type: "control"`). */
    fun control(message: MaxMessage): Attachment.Control? =
        message.attachments.firstNotNullOfOrNull { it as? Attachment.Control }

    fun isService(message: MaxMessage?): Boolean = message?.isService == true

    /** Подпись служебного [message] без знания аккаунта и имён; `null`, если сообщение не служебное. */
    fun text(message: MaxMessage): String? = text(message, selfId = null)

    /** Подпись служебного [message] по стору ядра: аккаунт — [MaxState.me], имена — [MaxState.displayName]. */
    fun text(message: MaxMessage, state: MaxState, fallbackChatId: Long? = null): String? =
        text(message, state.me, pinnedText = { id -> localText(state, message.chatId ?: fallbackChatId, id) }) { id -> state.displayName(id) }

    /**
     * Текст сообщения [messageId] из сообщений чата, которые уже есть в сторе ядра (лента,
     * история, пуши), — для закрепа, у которого сервер прислал только id; `null`, если его нет.
     */
    fun localText(state: MaxState, chatId: Long?, messageId: Long): String? {
        val messages = chatId?.let { state.messages[it] } ?: return null
        return messages.lastOrNull { it.id == messageId }?.text?.takeIf { it.isNotBlank() }
    }

    /**
     * Подпись служебного [message]; `null`, если сообщение не служебное. [selfId] — аккаунт,
     * [nameOf] — имя пользователя, известное клиенту, или `null`; [pinnedText] — текст
     * закреплённого сообщения по id, если сервер прислал в `pinnedMessage` только id.
     */
    fun text(
        message: MaxMessage,
        selfId: Long?,
        pinnedText: (Long) -> String? = { null },
        nameOf: (Long) -> String? = { null },
    ): String? {
        val control = control(message) ?: return null
        val pinned = control.pinnedMessageId?.takeIf { control.pinnedText.isNullOrBlank() }
            ?.let { id -> runCatching { pinnedText(id) }.getOrNull() }
        val core = runCatching {
            controlFallbackText(control, selfId = selfId, actorId = message.sender, pinnedText = pinned, nameOf = nameOf)
        }.getOrNull()
        core?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        message.text.trim().takeIf { it.isNotEmpty() }?.let { return it }
        logUnknown(control, message)
        return GENERIC
    }

    /** Строка для списка чатов: та же подпись в одну строку. */
    fun preview(message: MaxMessage): String? = oneLine(text(message))

    fun preview(message: MaxMessage, state: MaxState, fallbackChatId: Long? = null): String? = oneLine(text(message, state, fallbackChatId))

    /**
     * Уведомлять ли о служебном сообщении — как iOS (`SyncEngine`, 535c980): из событий чата только
     * «теперь в MAX» (`hello`, `new` личного чата); закрепление (`pin`, `unpin`) iOS событием не
     * считает и уведомляет о нём, как об обычном сообщении. Не служебное — `true`.
     */
    fun notifies(message: MaxMessage): Boolean {
        val control = control(message) ?: return true
        return when (control.event?.trim()?.lowercase().orEmpty()) {
            "pin", "unpin", "hello" -> true
            "new" -> control.chatType.equals("DIALOG", ignoreCase = true)
            else -> false
        }
    }

    private fun oneLine(text: String?): String? = text?.replace(Regex("\\s+"), " ")?.trim()

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
