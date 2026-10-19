package app.maxly.data

import app.maxly.domain.ChatType
import app.maxly.domain.IncomingMessageNotice
import com.maxly.core.api.MaxMessage
import com.maxly.core.events.MaxEvent
import com.maxly.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.mapNotNull

/**
 * Новые чужие сообщения из пушей ядра — для уведомлений, пока приложение не на экране.
 *
 * Сервер Max шлёт пуши только своему приложению, поэтому уведомление собирается на устройстве
 * из того, что пришло по соединению ядра. Берутся события после того, как ядро влило их в стор
 * (`appliedEvents`): название чата и имя автора уже известны. Свои сообщения, комментарии
 * к постам, служебные строки и повторы одного и того же сообщения не проходят.
 */
class IncomingMessages(private val client: MaxClient, private val clock: () -> Long = System::currentTimeMillis) {
    private val seen = RecentKeys(SEEN_LIMIT)

    val notices: Flow<IncomingMessageNotice> = client.appliedEvents
        .filterIsInstance<MaxEvent.NewMessage>()
        .mapNotNull { notice(it.message) }

    private fun notice(message: MaxMessage): IncomingMessageNotice? {
        val chatId = message.chatId ?: return null
        val state = client.store.state.value
        val sender = message.sender ?: return null
        if (sender == state.me || MessageMapping.isComment(message)) return null
        if (ServiceMessages.isService(message)) return null
        if (!seen.add("$chatId:${message.id}")) return null
        val now = clock()
        val chat = state.chats[chatId]?.let { ChatMapping.chat(it, state, client.accountConfig.value, now, mutes = ChatMutes.of(client)) }
        val mapped = MessageMapping.message(message, chatId, state)
        return IncomingMessageNotice(
            chatId = chatId.toString(),
            messageId = message.id.toString(),
            chatTitle = chat?.title.orEmpty(),
            chatType = chat?.type ?: ChatType.PRIVATE,
            authorName = mapped.authorName,
            text = mapped.text,
            media = MessageMapping.previewOf(mapped.content.attachments),
            isMuted = chat?.isMuted ?: false,
            timeMs = message.time,
        )
    }

    private companion object {
        const val SEEN_LIMIT = 500
    }
}

/** Последние [limit] ключей: [add] ложно для повтора. */
internal class RecentKeys(private val limit: Int) {
    private val keys = LinkedHashSet<String>()

    @Synchronized
    fun add(key: String): Boolean {
        if (!keys.add(key)) return false
        if (keys.size > limit) keys.remove(keys.first())
        return true
    }
}
