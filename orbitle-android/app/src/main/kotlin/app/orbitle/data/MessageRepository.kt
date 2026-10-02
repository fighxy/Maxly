package app.orbitle.data

import app.orbitle.domain.Chat
import app.orbitle.domain.Message
import kotlinx.coroutines.flow.Flow

/** Шапка чата: сам чат и живые данные для второй строки. */
data class ChatHeaderInfo(
    val chat: Chat,
    /** Участники группы или подписчики канала, если сервер их назвал. */
    val participants: Int? = null,
    /** Когда собеседник был в сети (мс), 0 — неизвестно. */
    val lastSeenMs: Long = 0,
    /** Кто печатает прямо сейчас (имена). */
    val typing: List<String> = emptyList(),
)

/** История одного чата и действия над сообщениями. */
interface MessageRepository {
    /** Id своего аккаунта, `null` до входа. */
    val currentUserId: String?

    /** Лента чата от старых к новым, вместе с ещё не ушедшими своими сообщениями. */
    fun messages(chatId: String): Flow<List<Message>>

    /** Шапка чата; `null`, пока чат не известен. */
    fun header(chatId: String): Flow<ChatHeaderInfo?>

    /** Свежая страница истории. */
    suspend fun loadLatest(chatId: String)

    /** Страница старше самого раннего сообщения. `false` — история кончилась. */
    suspend fun loadOlder(chatId: String): Boolean

    /** Отправка текста. Сообщение сразу встаёт в ленту, при ошибке остаётся с пометкой. */
    suspend fun send(chatId: String, text: String, replyTo: String?)

    /** Повторить не ушедшее сообщение. */
    suspend fun retry(chatId: String, localId: String)

    /** Убрать не ушедшее сообщение из ленты. */
    fun discard(chatId: String, localId: String)

    suspend fun edit(chatId: String, messageId: String, text: String)

    suspend fun delete(chatId: String, messageIds: List<String>, forEveryone: Boolean)

    /** Отметить прочитанным всё до [messageId] включительно. */
    suspend fun markRead(chatId: String, messageId: String)

    /** Поставить реакцию или снять свою (`null`). */
    suspend fun react(chatId: String, messageId: String, emoji: String?)

    /** Эмодзи реакций из каталога сервера. */
    suspend fun reactionCatalog(): List<String>
}
