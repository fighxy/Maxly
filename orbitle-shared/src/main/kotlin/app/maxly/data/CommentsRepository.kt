package app.maxly.data

import app.maxly.domain.Message
import app.maxly.domain.MessageReaction
import app.maxly.domain.MaxlyError
import com.maxly.shared.MaxClient

/** Комментарии под постами канала. */
interface CommentsRepository {
    /** До [limit] комментариев строго старше [beforeMs] (самые новые, если `null`), от старых к новым. */
    suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message>

    /**
     * Первая страница обсуждения: самые новые комментарии. [postTimeMs] — время поста,
     * [expectedCount] — сколько комментариев насчитал сервер (`null` — неизвестно).
     */
    suspend fun firstComments(chatId: String, postId: String, postTimeMs: Long?, expectedCount: Int?, limit: Int): List<Message> =
        comments(chatId, postId, null, limit)

    /** Отправляет комментарий и возвращает его в том виде, в каком его принял сервер. */
    suspend fun send(text: String, chatId: String, postId: String): Message

    /** Число комментариев под постами: id поста → число. Посты, о чьём обсуждении сервер не сообщил, не входят. */
    suspend fun counts(chatId: String, postIds: List<String>): Map<String, Int> = emptyMap()

    /** Своя реакция на комментарий или её снятие (`null`). Ответ — реакции от сервера, если он их прислал. */
    suspend fun setReaction(chatId: String, postId: String, commentId: String, emoji: String?): List<MessageReaction>? =
        throw MaxlyError.Rejected("Реакции недоступны")
}

class CoreCommentsRepository(
    private val client: MaxClient,
    private val clock: () -> Long = System::currentTimeMillis,
) : CommentsRepository {
    override suspend fun comments(chatId: String, postId: String, beforeMs: Long?, limit: Int): List<Message> =
        page(chatId, postId, CommentPage.before(beforeMs, clock(), limit)).filter { beforeMs == null || it.timeMs < beforeMs }

    override suspend fun firstComments(chatId: String, postId: String, postTimeMs: Long?, expectedCount: Int?, limit: Int): List<Message> {
        val newest = comments(chatId, postId, null, limit)
        if (newest.isNotEmpty() || postTimeMs == null || expectedCount == 0) return newest
        // Страница назад пришла пустой, а комментарии под постом могут быть: один запрос вперёд
        // от времени поста. Так обсуждение читает и эталонный клиент.
        return page(chatId, postId, CommentPage.afterPost(postTimeMs, limit))
    }

    private suspend fun page(chatId: String, postId: String, request: CommentPage): List<Message> {
        val chat = chatId.toLong()
        val page = MaxCoreGateway.read {
            client.api.messages.getCommentHistory(chat, postId.toLong(), from = request.from, backward = request.backward, forward = request.forward)
        }
        val known = client.store.state.value.users
        val missing = page.mapNotNull { it.sender }.filter { it != 0L && it !in known }.distinct()
        // Без имён список всё равно показывается: такие авторы выйдут без подписи.
        if (missing.isNotEmpty()) runCatching { missing.chunked(100).forEach { MaxCoreGateway.read { client.loadUsers(it) } } }
        val state = client.store.state.value
        return page.distinctBy { it.id }
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
        // Запись без `commentsInfo` значит, что сервер не сообщил об обсуждении поста: такой
        // пост не получает счётчика, и плашку решает флаг комментариев канала.
        return MaxCoreGateway.read { client.api.messages.getCommentsInfo(chatId.toLong(), ids) }
            .mapNotNull { info -> info.totalCount?.let { info.postId.toString() to maxOf(0, it) } }
            .toMap()
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

/**
 * Поля `from`, `backward` и `forward` запроса комментариев (`CHAT_HISTORY` с `postId`).
 * [from] — всегда настоящее время в миллисекундах, как у обычной истории: самые новые
 * комментарии — страница назад от текущего момента. Значение -1 (умолчание ядра) не момент
 * времени; эталонный клиент всегда шлёт настоящее время.
 */
internal data class CommentPage(val from: Long, val backward: Int, val forward: Int) {
    companion object {
        /** Больше этого сервер за раз не отдаёт. */
        const val MAX_PAGE = 100

        /** До [limit] комментариев раньше [beforeMs]; без него — самые новые на [nowMs]. */
        fun before(beforeMs: Long?, nowMs: Long, limit: Int) = CommentPage(beforeMs ?: nowMs, limit.coerceIn(1, MAX_PAGE), 0)

        /** Первые [limit] комментариев после поста: запасной запрос, если страница назад пуста. */
        fun afterPost(postTimeMs: Long, limit: Int) = CommentPage(postTimeMs, 0, limit.coerceIn(1, MAX_PAGE))
    }
}
