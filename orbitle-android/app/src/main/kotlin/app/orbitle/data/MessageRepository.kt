package app.orbitle.data

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatAttachment
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.OutgoingFile
import app.orbitle.domain.Message
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

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

    /**
     * Отправка вложений одним сообщением с подписью. Сообщение сразу встаёт в ленту;
     * [progress] получает долю загрузки 0…1.
     */
    suspend fun sendMedia(chatId: String, items: List<OutgoingFile>, caption: String, replyTo: String?, progress: (Float) -> Unit = {}): Unit =
        throw OrbitleError.Rejected("Отправка вложений недоступна")

    /** Отправить стикер каталога. */
    suspend fun sendSticker(chatId: String, sticker: app.orbitle.domain.Sticker, replyTo: String?): Unit =
        throw OrbitleError.Rejected("Стикеры недоступны")

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

    /**
     * Расшифровка голосового [voiceId] сообщения [messageId]. `null` — сервер ещё расшифровывает,
     * готовый текст придёт в [transcriptions].
     */
    suspend fun transcribe(chatId: String, messageId: String, voiceId: String): String? = throw OrbitleError.Rejected("Расшифровка недоступна")

    /** Готовые расшифровки, присланные сервером позже: id сообщения → текст. */
    fun transcriptions(): Flow<Pair<String, String>> = emptyFlow()

    /** Прямой адрес видео или файла сообщения для плеера и загрузки. */
    /** Кто отреагировал на сообщение. */
    suspend fun reactionUsers(chatId: String, messageId: String): List<app.orbitle.domain.ReactionUser> =
        throw OrbitleError.Rejected("Список недоступен")

    /** Пересылает сообщение [messageId] из [chatId] в чат [targetChatId]. */
    suspend fun forward(chatId: String, messageId: String, targetChatId: String): Unit = throw OrbitleError.Rejected("Пересылка недоступна")

    suspend fun mediaLink(chatId: String, messageId: String, attachment: ChatAttachment): String = throw OrbitleError.Rejected("Вложение недоступно")
}
