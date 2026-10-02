package app.orbitle.data

import app.orbitle.domain.Message
import app.orbitle.domain.MessageReaction
import app.orbitle.domain.OrbitleError
import com.max.shared.MaxClient

/** Комментарии под постами канала. */
interface CommentsRepository {
    /** До [limit] комментариев строго старше [beforeMs] (самые новые, если `null`), от старых к новым. */
    suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message>

    /** Отправляет комментарий и возвращает его в том виде, в каком его принял сервер. */
    suspend fun send(text: String, chatId: String, postId: String): Message

    /** Число комментариев под постами: id поста → число. Без счётчиков плашка покажет «Комментировать». */
    suspend fun counts(chatId: String, postIds: List<String>): Map<String, Int> = emptyMap()

    /** Своя реакция на комментарий или её снятие (`null`). Ответ — реакции от сервера, если он их прислал. */
    suspend fun setReaction(chatId: String, postId: String, commentId: String, emoji: String?): List<MessageReaction>? =
        throw OrbitleError.Rejected("Реакции недоступны")
}

class CoreCommentsRepository(private val client: MaxClient) : CommentsRepository {
    override suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message> {
        val chat = chatId.toLong()
        val page = MaxCoreGateway.call {
            client.api.messages.getCommentHistory(chat, postId.toLong(), from = beforeMs ?: -1, backward = limit.coerceIn(1, 100))
        }
        val known = client.store.state.value.users
        val missing = page.mapNotNull { it.sender }.filter { it != 0L && it !in known }.distinct()
        // Без имён список всё равно показывается: такие авторы выйдут без подписи.
        if (missing.isNotEmpty()) runCatching { missing.chunked(100).forEach { MaxCoreGateway.call { client.loadUsers(it) } } }
        val state = client.store.state.value
        return page.filter { beforeMs == null || it.time < beforeMs }
            .sortedBy { it.time }
            .map { MessageMapping.message(it, chat, state) }
    }

    override suspend fun send(text: String, chatId: String, postId: String): Message {
        val chat = chatId.toLong()
        val sent = MaxCoreGateway.call { client.api.messages.sendComment(chat, postId.toLong(), text) }
        return MessageMapping.message(sent, chat, client.store.state.value)
    }

    override suspend fun counts(chatId: String, postIds: List<String>): Map<String, Int> {
        val ids = postIds.mapNotNull { it.toLongOrNull() }.distinct()
        if (ids.isEmpty()) return emptyMap()
        return MaxCoreGateway.call { client.api.messages.getCommentsInfo(chatId.toLong(), ids) }
            .associate { it.postId.toString() to maxOf(0, it.totalCount ?: 0) }
    }

    override suspend fun setReaction(chatId: String, postId: String, commentId: String, emoji: String?): List<MessageReaction>? {
        val chat = chatId.toLong()
        val post = postId.toLong()
        val id = commentId.toLong()
        val info = MaxCoreGateway.call {
            if (emoji == null) client.api.messages.removeCommentReaction(chat, post, id)
            else client.api.messages.addCommentReaction(chat, post, id, emoji)
        } ?: return null
        return MessageMapping.reactions(info.raw)
    }
}
