package app.orbitle.data

import com.max.core.api.ReadState
import com.max.core.events.MaxEvent
import com.max.core.protocol.Opcode
import com.max.core.state.MaxState
import com.max.shared.MaxClient
import com.max.core.api.Chat as CoreChat

/**
 * Отметки прочтения: своя и собеседников. Отметка — время (мс): всё, что отправлено не позже
 * неё, прочитано. Она живёт в двух местах стора: в `participants` карточки чата (приходит со
 * списком чатов) и в `readMarks` (пуши `NOTIF_MARK` и ответы на свою отметку). Карточка чата
 * от пуша не меняется, поэтому учитываются оба источника — берётся более свежая отметка.
 */
internal object ReadMarks {

    /** Свежая отметка других участников чата (мс). У каналов отметок собеседников нет. */
    fun peer(chat: CoreChat, state: MaxState): Long {
        if (chat.type == "CHANNEL") return 0L
        val pushed = state.readMarks[chat.id].orEmpty().filterKeys { it != state.me }.values.maxOrNull() ?: 0L
        return maxOf(ChatMapping.peerReadMark(chat, state.me), pushed)
    }

    /** Своя отметка прочтения в чате (мс). */
    fun own(chat: CoreChat, state: MaxState): Long {
        val me = state.me ?: return 0L
        val listed = (chat.raw["participants"] as? Map<*, *>)?.entries
            ?.firstOrNull { ChatMapping.longOf(it.key) == me }?.value
            ?.let(ChatMapping::longOf) ?: 0L
        return maxOf(listed, state.readMarks[chat.id]?.get(me) ?: 0L)
    }

    /**
     * Время сообщения [messageId] на сервере: им ставится отметка. Часы устройства могут
     * отставать от сервера, и отметка «сейчас» оказалась бы раньше только что пришедших
     * сообщений — они остались бы непрочитанными и на сервере, и у собеседника.
     */
    fun messageTime(state: MaxState, chatId: Long, messageId: Long): Long? =
        state.messagesOf(chatId).firstOrNull { it.id == messageId }?.time
            ?: state.chats[chatId]?.lastMessage?.takeIf { it.id == messageId }?.time

    /**
     * Сколько непрочитанных оставить в карточке чата после ответа сервера на отметку. Стор
     * пересчитывает счётчик сам, но с неполной историей держит прежний счётчик сервера. Ответ
     * сервера ([serverUnread]) точнее, если с запроса в чат не пришло ничего нового (последнее
     * сообщение то же, [lastBefore]) и он меньше того, что в сторе. `null` — оставить как есть.
     */
    fun unreadAfterRead(chat: CoreChat?, lastBefore: Long?, serverUnread: Int): Int? {
        if (chat == null || serverUnread < 0) return null
        if (chat.lastMessage?.id != lastBefore) return null
        return serverUnread.takeIf { it < chat.newMessages }
    }

    /**
     * Ответ на отметку [mark] не старее своей отметки в сторе. Ответы на две отметки подряд
     * могут прийти в обратном порядке: запоздавший ответ на старую не должен откатывать новую
     * и возвращать счётчик непрочитанных.
     */
    fun isFresh(state: MaxState, chatId: Long, mark: Long): Boolean {
        val me = state.me ?: return false
        return mark >= (state.readMarks[chatId]?.get(me) ?: 0L)
    }

    /**
     * Прочитать чат [chatId] до сообщения [messageId]: отметка уходит временем сообщения, стор
     * получает ответ сервера сразу, не дожидаясь пуша.
     */
    suspend fun send(client: MaxClient, chatId: Long, messageId: Long) {
        val before = client.store.state.value
        val lastBefore = before.chats[chatId]?.lastMessage?.id
        val time = messageTime(before, chatId, messageId)
        val reply: ReadState = MaxCoreGateway.call { client.api.messages.markRead(chatId, messageId, time) }
        val me = client.store.state.value.me ?: return
        if (!isFresh(client.store.state.value, chatId, reply.mark)) return
        client.store.apply(MaxEvent.MessageRead(chatId, me, reply.mark, false, Opcode.CHAT_MARK.value, null))
        val after = client.store.state.value.chats[chatId] ?: return
        unreadAfterRead(after, lastBefore, reply.unread)?.let { unread ->
            client.store.putChats(listOf(after.copy(newMessages = unread)))
        }
    }
}
