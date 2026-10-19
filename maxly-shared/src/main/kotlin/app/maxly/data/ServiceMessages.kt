package app.maxly.data

import app.maxly.domain.PinNotice
import com.maxly.core.api.MaxMessage
import com.maxly.core.state.MaxState
import com.maxly.core.media.Attachment
import com.maxly.core.media.controlFallbackText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Событие чата из вложения `CONTROL` (кроме закрепления): событие, участники (id строками,
 * без `0`), название, тип чата и текст сервера (`shortMessage`, `message`, `text` вложения).
 * Тот же разбор, что у iOS (`MessageContentCodec.serviceNotice`).
 */
data class ServiceNotice(
    val event: String,
    val userId: String? = null,
    val userIds: List<String> = emptyList(),
    val title: String? = null,
    val text: String? = null,
    val chatType: String? = null,
) {
    /** Все участники события: `userId`, затем `userIds`, без повторов. */
    val participantIds: List<String>
        get() = (listOfNotNull(userId) + userIds).filter { it.isNotEmpty() }.distinct()
}

/** Вид события по `event` (без учёта регистра); [fixtureName] — имя в общих сценариях. */
enum class ServiceKind(val fixtureName: String) {
    /** Контакт зарегистрировался: `hello` или `new` личного чата. */
    JOINED("joined"),
    CREATED("created"),
    ADDED("added"),
    REMOVED("removed"),
    LEFT("left"),
    JOINED_BY_LINK("joinedByLink"),
    RENAMED("renamed"),
    PHOTO("photo"),
    BOT_STARTED("botStarted"),
    SYSTEM("system"),
    UNKNOWN("unknown"),
}

/**
 * Служебные сообщения: вложение `CONTROL`. Правила текста общие с iOS
 * (`test-fixtures/service-messages/README.md`, Swift — `ServiceText`):
 *
 * 1. Текст ядра ([controlFallbackText]: свой у `new` и `botStarted`, у остальных событий —
 *    `shortMessage`, затем `message` сервера) важнее своего, кроме «теперь в MAX» для `new`
 *    личного чата (там ядро пишет общее «Чат создан»).
 * 2. Иначе свой текст: своё событие — от «Вы», чужое — имя и глагол с «(а)», аккаунт — «вас»,
 *    имена участников — из контактов и известных пользователей, без имени — счётом.
 * 3. `system` и незнакомое событие — текст сервера, затем текст сообщения, иначе [GENERIC].
 *
 * Закрепление (`pin`, `unpin`) — не событие: у него своя строка, как на iOS
 * («Закреплено: …», «Сообщение закреплено», «Закрепление снято»).
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

    /** Вложение `CONTROL` (ключ `_type` или `type`, регистр не важен). */
    fun isControl(value: Any?): Boolean {
        val map = value as? Map<*, *> ?: return false
        return ((map["_type"] ?: map["type"]) as? String)?.uppercase() == "CONTROL"
    }

    private fun controlMap(attaches: List<*>?): Map<*, *>? =
        attaches.orEmpty().firstOrNull(::isControl) as? Map<*, *>

    /** `CONTROL` сообщения в разборе ядра (его же читает [controlFallbackText]). */
    fun control(message: MaxMessage): Attachment.Control? = controlMap(message.attaches)?.let(::coreControl)

    private fun coreControl(map: Map<*, *>): Attachment.Control =
        (Attachment.from(map) as? Attachment.Control) ?: Attachment.Control(
            event = map["event"] as? String,
            userId = ChatMapping.longOf(map["userId"]),
            userIds = (map["userIds"] as? List<*>).orEmpty().mapNotNull { ChatMapping.longOf(it) },
            title = map["title"] as? String,
            url = map["url"] as? String,
            chatType = map["chatType"] as? String,
            raw = map,
            message = map["message"] as? String,
            shortMessage = map["shortMessage"] as? String,
        )

    fun isService(message: MaxMessage?): Boolean = message != null && controlMap(message.attaches) != null

    /** Событие чата из вложений или `null`: `CONTROL` нет или это закрепление. */
    fun notice(attaches: List<*>?): ServiceNotice? {
        for (item in attaches.orEmpty()) {
            if (!isControl(item)) continue
            val map = item as Map<*, *>
            val event = (map["event"] as? String)?.trim().orEmpty()
            if (event.lowercase() in PIN_EVENTS) continue
            val ids = (map["userIds"] as? List<*>).orEmpty().mapNotNull(::stringId).filter { it != "0" }
            val single = stringId(map["userId"])?.takeIf { it != "0" }
            val text = listOf("shortMessage", "message", "text").firstNotNullOfOrNull { key -> clean(map[key] as? String) }
            return ServiceNotice(
                event = event,
                userId = single,
                userIds = ids,
                title = clean(map["title"] as? String),
                text = text,
                chatType = (map["chatType"] as? String)?.takeIf { it.isNotEmpty() },
            )
        }
        return null
    }

    fun kind(notice: ServiceNotice): ServiceKind = when (notice.event.lowercase()) {
        "hello" -> ServiceKind.JOINED
        "new" -> if (notice.chatType?.uppercase() == "DIALOG") ServiceKind.JOINED else ServiceKind.CREATED
        "add" -> ServiceKind.ADDED
        "remove" -> ServiceKind.REMOVED
        "leave" -> ServiceKind.LEFT
        "joinbylink" -> ServiceKind.JOINED_BY_LINK
        "title" -> ServiceKind.RENAMED
        "icon" -> ServiceKind.PHOTO
        "botstarted" -> ServiceKind.BOT_STARTED
        "system" -> ServiceKind.SYSTEM
        else -> ServiceKind.UNKNOWN
    }

    /**
     * Текст события [notice].
     *
     * - [actorId], [actorName] — отправитель сообщения (автор события);
     * - [viewerId] — аккаунт: его событие пишется от «Вы», он сам в участниках — «вас»;
     * - [names] — имена, известные клиенту (id → имя);
     * - [messageText] — текст самого сообщения (для `system` и незнакомых событий);
     * - [coreText] — текст ядра ([controlFallbackText]).
     */
    fun text(
        notice: ServiceNotice,
        actorId: String,
        actorName: String?,
        viewerId: String?,
        names: (String) -> String? = { null },
        messageText: String = "",
        coreText: String? = null,
    ): String {
        val viewer = viewerId.orEmpty()
        val mine = viewer.isNotEmpty() && actorId == viewer
        val actor = if (mine) "Вы" else clean(actorName) ?: clean(names(actorId)) ?: "Участник"
        fun action(past: String, plural: String) = if (mine) "Вы $plural" else "$actor $past"
        val title = clean(notice.title)
        val targets = notice.participantIds
        val onlyActor = targets.isEmpty() || targets == listOf(actorId)
        val kind = kind(notice)
        // «Теперь в MAX» для `new` личного чата ядро не различает и пишет «Чат создан».
        val genericCore = kind == ServiceKind.JOINED && notice.event.lowercase() == "new"
        if (!genericCore) clean(coreText)?.let { return it }
        val list = { ids: List<String> -> list(ids, viewer, actorId, actorName, names) }
        return when (kind) {
            ServiceKind.JOINED -> joined(notice, viewer, actorId, actorName, mine, names)
            ServiceKind.CREATED -> {
                val what = if (notice.chatType?.uppercase() == "CHANNEL") "канал" else "чат"
                val base = action("создал(а) $what", "создали $what")
                title?.let { "$base «$it»" } ?: base
            }
            ServiceKind.ADDED ->
                if (onlyActor) action("вступил(а) в чат", "вступили в чат")
                else action("добавил(а)", "добавили") + " " + list(targets)
            ServiceKind.REMOVED -> when {
                targets.isEmpty() -> action("удалил(а) участника", "удалили участника")
                targets == listOf(actorId) -> action("покинул(а) чат", "покинули чат")
                else -> action("удалил(а)", "удалили") + " " + list(targets)
            }
            ServiceKind.LEFT -> action("покинул(а) чат", "покинули чат")
            ServiceKind.JOINED_BY_LINK -> action("вступил(а) в чат по ссылке", "вступили в чат по ссылке")
            ServiceKind.RENAMED ->
                if (title == null) action("изменил(а) название чата", "изменили название чата")
                else action("изменил(а) название на «$title»", "изменили название на «$title»")
            ServiceKind.PHOTO -> action("изменил(а) фото чата", "изменили фото чата")
            ServiceKind.BOT_STARTED -> action("запустил(а) бота", "запустили бота")
            ServiceKind.SYSTEM, ServiceKind.UNKNOWN -> clean(notice.text) ?: clean(messageText) ?: title ?: GENERIC
        }
    }

    /** «<Имя> теперь в MAX»: имя того, о ком событие (`userId`, иначе отправитель). */
    private fun joined(notice: ServiceNotice, viewer: String, actorId: String, actorName: String?, mine: Boolean, names: (String) -> String?): String {
        val subject = notice.participantIds.firstOrNull() ?: actorId
        if ((viewer.isNotEmpty() && subject == viewer) || (mine && subject == actorId)) return "Вы теперь в MAX"
        val name = clean(names(subject)) ?: (if (subject == actorId) clean(actorName) else null) ?: "Контакт"
        return "$name теперь в MAX"
    }

    /** Участники через запятую и «и»; аккаунт — «вас», без имени — счётом. */
    private fun list(ids: List<String>, viewer: String, actorId: String, actorName: String?, names: (String) -> String?): String {
        val known = mutableListOf<String>()
        var unknown = 0
        for (id in ids) {
            val name = when {
                viewer.isNotEmpty() && id == viewer -> "вас"
                else -> clean(names(id)) ?: if (id == actorId) clean(actorName) else null
            }
            if (name != null) known += name else unknown++
        }
        if (known.isEmpty()) return if (unknown == 1) "участника" else "$unknown ${participants(unknown)}"
        if (unknown > 0) return known.joinToString(", ") + " и ещё $unknown"
        if (known.size == 1) return known[0]
        return known.dropLast(1).joinToString(", ") + " и " + known.last()
    }

    /** «2 участника», «5 участников», «21 участника» (винительный падеж). */
    fun participants(count: Int): String {
        val tens = count % 100
        val ones = count % 10
        if (tens in 11..14) return "участников"
        return if (ones in 1..4) "участника" else "участников"
    }

    /** Строка закрепления, как плашка iOS: «Закреплено: …», «Сообщение закреплено», «Закрепление снято». */
    fun pinText(pin: PinNotice?): String = when {
        pin == null -> "Сообщение закреплено"
        pin.messageId.isNullOrEmpty() -> "Закрепление снято"
        pin.preview.isEmpty() -> "Сообщение закреплено"
        else -> "Закреплено: ${pin.preview}"
    }

    /** Подпись служебного [message] без знания аккаунта и имён; `null`, если сообщение не служебное. */
    fun text(message: MaxMessage): String? = text(message, viewerId = null)

    /** Подпись служебного [message] по стору ядра: аккаунт — [MaxState.me], имена — [MaxState.displayName]. */
    fun text(message: MaxMessage, state: MaxState): String? =
        text(message, state.me?.toString(), { id -> id.toLongOrNull()?.let(state::displayName) })

    /** Подпись служебного [message]; `null`, если сообщение не служебное. */
    fun text(
        message: MaxMessage,
        viewerId: String?,
        names: (String) -> String? = { null },
        actorName: String? = message.sender?.toString()?.let(names),
    ): String? {
        val map = controlMap(message.attaches) ?: return null
        val notice = notice(message.attaches) ?: return pinText(MessageMapping.pinNotice(message.attaches))
        val control = coreControl(map)
        val actorId = message.sender?.toString().orEmpty()
        val text = text(
            notice,
            actorId = actorId,
            actorName = actorName,
            viewerId = viewerId,
            names = names,
            messageText = message.text,
            coreText = runCatching { controlFallbackText(control) }.getOrNull(),
        )
        if (text == GENERIC) logUnknown(control, message)
        return text
    }

    /** Строка для списка чатов: та же подпись в одну строку. */
    fun preview(message: MaxMessage): String? = oneLine(text(message))

    fun preview(message: MaxMessage, state: MaxState): String? = oneLine(text(message, state))

    /**
     * Служебное сообщение достойно уведомления, как на iOS (`SyncEngine`): из событий чата — только
     * «теперь в MAX» ([ServiceKind.JOINED]); закрепление уведомляет как обычное сообщение.
     */
    fun notifies(message: MaxMessage): Boolean {
        if (!isService(message)) return true
        val notice = notice(message.attaches) ?: return true
        return kind(notice) == ServiceKind.JOINED
    }

    private fun oneLine(text: String?): String? = text?.replace(Regex("\\s+"), " ")?.trim()

    private fun stringId(value: Any?): String? = when (value) {
        is String -> value.trim().takeIf { it.isNotEmpty() }
        is Number -> value.toLong().toString()
        else -> null
    }

    private fun clean(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

    private val PIN_EVENTS = setOf("pin", "unpin")

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
