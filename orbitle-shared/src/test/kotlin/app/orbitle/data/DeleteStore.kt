package app.orbitle.data

import app.orbitle.domain.DeletePlan
import app.orbitle.domain.Message
import app.orbitle.domain.MessageStatus
import com.max.core.api.Chat
import com.max.core.api.ChatRights
import com.max.core.api.MaxMessage
import com.max.core.api.MessageDeletion
import com.max.core.state.MaxState

/**
 * Стор ядра для правил удаления в тестах: чат вида [type] (`DIALOG`, `CHAT`, `CHANNEL`; `null` —
 * чата в сторе нет) и ушедшие сообщения. [admin] — свой админ с правом удалять чужое: в группе
 * бит 1, в канале бит 1024 (`ChatPermission` ядра); [permissions] — свои биты админа явно,
 * [owner] — свой чат. План — как у `CoreMessageRepository`, только часы — [nowMs].
 */
object DeleteStore {
    fun plan(
        me: String?,
        chatId: String,
        type: String?,
        admin: Boolean,
        messages: List<Message>,
        editTimeoutSeconds: Long,
        nowMs: Long,
        permissions: Long? = null,
        owner: Boolean = false,
    ): DeletePlan {
        val id = chatId.toLong()
        val myId = me?.toLongOrNull()
        val chat = type?.let {
            val raw = linkedMapOf<String, Any?>("id" to id, "type" to it)
            val bits = permissions ?: if (admin) (if (it == "CHANNEL") 1024L else 1L) else null
            if (bits != null && myId != null) raw["adminParticipants"] = mapOf(myId.toString() to mapOf("permissions" to bits))
            if (owner && myId != null) raw["owner"] = myId
            Chat.from(raw)
        }
        val stored = messages.filter { it.status == MessageStatus.SENT }.mapNotNull { m ->
            val messageId = m.id.toLongOrNull() ?: return@mapNotNull null
            MaxMessage.from(mapOf("id" to messageId, "time" to m.timeMs, "sender" to m.authorId.toLongOrNull(), "text" to m.text, "type" to "USER"), id)
        }.sortedWith(compareBy({ it.time }, { it.id }))
        val state = MaxState(
            me = myId,
            chats = chat?.let { mapOf(id to it) }.orEmpty(),
            messages = if (stored.isEmpty()) emptyMap() else mapOf(id to stored),
        )
        return DeletePlans.of(chatId, chat, ChatRights.of(chat, myId), messages) { ids ->
            MessageDeletion.plan(state, id, ids, editTimeoutSeconds, nowMs)
        }
    }
}
