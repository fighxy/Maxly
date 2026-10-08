package app.orbitle.data

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

    /**
     * Своя отметка прочтения в чате (мс): по ней встаёт разделитель непрочитанных. Берётся самая
     * свежая из трёх: запись в карточке чата, пуш `NOTIF_MARK` и местная отметка
     * ([MaxState.localReads]). Местная появляется, когда отметки о прочтении скрыты и сервер свою
     * не получает: без неё разделитель каждый раз возвращался бы к серверной.
     */
    fun own(chat: CoreChat, state: MaxState): Long {
        val me = state.me ?: return 0L
        val listed = (chat.raw["participants"] as? Map<*, *>)?.entries
            ?.firstOrNull { ChatMapping.longOf(it.key) == me }?.value
            ?.let(ChatMapping::longOf) ?: 0L
        return maxOf(listed, state.readMarks[chat.id]?.get(me) ?: 0L, state.localReads[chat.id]?.time ?: 0L)
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
     * Прочитать чат [chatId] до сообщения [messageId] через ядро ([MaxClient.markRead]): отметка
     * уходит временем сообщения, стор получает ответ сервера сразу, не дожидаясь пуша. Когда
     * отметки о прочтении скрыты, ядро ничего не отправляет и читает чат только на устройстве.
     * Своих запросов отметки клиент не шлёт.
     */
    suspend fun send(client: MaxClient, chatId: Long, messageId: Long) {
        val time = messageTime(client.store.state.value, chatId, messageId)
        MaxCoreGateway.call { client.markRead(chatId, messageId, time) }
    }
}
