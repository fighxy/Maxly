package app.maxly.data

import app.maxly.domain.FoundMessage
import java.util.LinkedHashMap

/**
 * Тела запросов, которых нет методом в зафиксированном ядре:
 * поиск в чате, жалобы, общие чаты, сигнал звонка и имя при добавлении контакта.
 */
object LockPayloads {
    const val COMPLAINT_CHANNEL = 2
    const val COMPLAINT_USER = 6
    const val IN_CHAT_COUNT = 30

    /** `hexCapability` в теле запроса звонка. */
    const val CALL_HEX_CAPABILITY = "3c02f"

    fun inChatSearch(chatId: Long, query: String, count: Int = IN_CHAT_COUNT): Map<String, Any?> =
        linkedMapOf("chatId" to chatId, "query" to query.trim(), "count" to count)

    fun complaintReasons(): Map<String, Any?> = linkedMapOf("complainSync" to 0)

    fun complaint(reasonId: Int, typeId: Int, ids: List<Long>, parentId: Long? = null): Map<String, Any?> {
        val payload = linkedMapOf<String, Any?>("reasonId" to reasonId, "typeId" to typeId, "ids" to ids)
        if (parentId != null) payload["parentId"] = parentId
        return payload
    }

    fun commonChats(userId: Long): Map<String, Any?> = linkedMapOf("userIds" to listOf(userId))

    /**
     * `CHAT_CLEAR` 54. Те же три поля, что у `ChatsApi.deleteChat` (`CHAT_DELETE` 52):
     * `chatId`, `lastEventTime`, `forAll`. Других полей в проверенном теле нет.
     */
    fun clearHistory(chatId: Long, lastEventTime: Long, forAll: Boolean): Map<String, Any?> =
        linkedMapOf("chatId" to chatId, "lastEventTime" to lastEventTime, "forAll" to forAll)

    /** `CONTACT_UPDATE` 34. Пустое имя не отправляется: остаётся прежнее тело без `firstName`. */
    fun addContact(userId: Long, firstName: String? = null): Map<String, Any?> {
        val payload = linkedMapOf<String, Any?>("contactId" to userId, "action" to "ADD")
        val name = firstName?.trim().orEmpty()
        if (name.isNotEmpty()) payload["firstName"] = name
        return payload
    }

    /** JSON для `internalParams`. Порядок ключей фиксирован. Медиа этим телом не открывается. */
    fun callInternalParams(deviceId: String): String = buildString {
        append("{\"platform\":\"ANDROID\",\"sdkVersion\":\"0.2.1.3\",\"clientAppKey\":\"CGPGAGLGDIHBABABA\",\"deviceId\":")
        append(jsonString(deviceId))
        append(",\"protocolVersion\":5,\"onlyAdminCanRecord\":false,\"isWaitForAdminEnabled\":false,\"hexCapability\":\"")
        append(CALL_HEX_CAPABILITY)
        append("\"}")
    }

    fun initiateCall(conversationId: String, calleeId: Long, deviceId: String, isVideo: Boolean): Map<String, Any?> =
        linkedMapOf(
            "conversationId" to conversationId,
            "calleeIds" to listOf(calleeId),
            "internalParams" to callInternalParams(deviceId),
            "isVideo" to isVideo,
        )

    fun createConference(conversationId: String): Map<String, Any?> = linkedMapOf("conversationId" to conversationId)

    fun createJoinLink(conversationId: String): Map<String, Any?> = linkedMapOf("conversationId" to conversationId)

    fun joinByLink(joinLink: String, deviceId: String, isVideo: Boolean): Map<String, Any?> =
        linkedMapOf(
            "joinLink" to joinLink,
            "internalParams" to callInternalParams(deviceId),
            "isVideo" to isVideo,
        )

    /** Первая строка `"endpoint"` внутри JSON ответа звонка. */
    fun endpointOf(json: String?): String? {
        if (json.isNullOrBlank()) return null
        val needle = "\"endpoint\""
        val at = json.indexOf(needle)
        if (at < 0) return null
        var i = json.indexOf(':', at + needle.length)
        if (i < 0) return null
        i++
        while (i < json.length && json[i].isWhitespace()) i++
        if (i >= json.length || json[i] != '"') return null
        i++
        val out = StringBuilder()
        while (i < json.length) {
            val c = json[i]
            if (c == '\\' && i + 1 < json.length) {
                out.append(json[i + 1])
                i += 2
                continue
            }
            if (c == '"') return out.toString().takeIf { it.isNotEmpty() }
            out.append(c)
            i++
        }
        return null
    }

    /** Ответ `MSG_SEARCH`: хит `{chatId, message}` или карта самого сообщения. */
    fun foundMessages(fallbackChatId: Long, result: Any?, me: Long?): List<FoundMessage> {
        val list = result as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val nested = map["message"] as? Map<*, *>
            val body = nested ?: map
            val id = ChatMapping.longOf(body["id"]) ?: return@mapNotNull null
            val chatId = ChatMapping.longOf(map["chatId"])?.takeIf { it != 0L }
                ?: ChatMapping.longOf(body["chatId"])?.takeIf { it != 0L }
                ?: fallbackChatId
            val sender = ChatMapping.longOf(body["sender"])
            FoundMessage(
                chatId = chatId.toString(),
                messageId = id.toString(),
                senderName = null,
                isOutgoing = sender != null && sender == me,
                text = (body["text"] as? String)?.trim().orEmpty(),
                timeMs = ChatMapping.longOf(body["time"]) ?: 0L,
            )
        }
    }

    fun complaintChoices(payload: Any?): Map<Int, List<ComplaintChoice>> {
        val map = payload as? Map<*, *> ?: return emptyMap()
        val complains = map["complains"] as? List<*> ?: return emptyMap()
        val out = LinkedHashMap<Int, List<ComplaintChoice>>()
        for (entry in complains) {
            val row = entry as? Map<*, *> ?: continue
            val typeId = ChatMapping.longOf(row["typeId"])?.toInt() ?: continue
            val reasons = (row["reasons"] as? List<*>).orEmpty().mapNotNull { item ->
                val reason = item as? Map<*, *> ?: return@mapNotNull null
                val id = ChatMapping.longOf(reason["reasonId"])?.toInt() ?: 0
                if (id == 0) null else ComplaintChoice(id, reason["reasonTitle"]?.toString().orEmpty())
            }
            out[typeId] = reasons
        }
        return out
    }

    fun sharedChats(payload: Any?): List<SharedChat> {
        val map = payload as? Map<*, *> ?: return emptyList()
        val chats = map["commonChats"] as? List<*> ?: return emptyList()
        return chats.mapNotNull { item ->
            val row = item as? Map<*, *> ?: return@mapNotNull null
            val id = ChatMapping.longOf(row["id"])?.takeIf { it != 0L } ?: return@mapNotNull null
            SharedChat(
                id = id.toString(),
                title = row["title"]?.toString().orEmpty().ifBlank { "Чат" },
                type = row["type"]?.toString()?.takeIf { it.isNotBlank() } ?: "CHAT",
            )
        }
    }

    private fun jsonString(value: String): String = buildString {
        append('"')
        for (c in value) {
            when (c) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                else -> append(c)
            }
        }
        append('"')
    }
}

data class ComplaintChoice(val id: Int, val title: String)

data class SharedChat(val id: String, val title: String, val type: String)

/** Участник группы или канала для листа. */
data class ChatMemberRow(
    val id: String,
    val name: String,
    /** Имя для упоминаний без «@» (`MaxUser.mentionName` ядра), если оно есть. */
    val mentionName: String? = null,
    /** Присутствие, если оно уже известно (стор или сама страница участников); `0` — неизвестно. */
    val isOnline: Boolean = false,
    val lastSeenMs: Long = 0,
)

/** Команда бота из `BOT_INFO` 145. */
data class BotCommandRow(val name: String, val description: String)

/**
 * Сервер принял сигнал звонка. [endpoint] — адрес сигналинга.
 * Звук и видео этот клиент не открывает.
 */
data class SignaledCall(val conversationId: String, val endpoint: String)
