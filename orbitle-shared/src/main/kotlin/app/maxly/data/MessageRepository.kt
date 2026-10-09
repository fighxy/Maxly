package app.maxly.data

import app.maxly.domain.Chat
import app.maxly.domain.ChatAttachment
import app.maxly.domain.OrbitleError
import app.maxly.domain.OutgoingFile
import app.maxly.domain.Message
import app.maxly.domain.PollContent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/** Шапка чата: сам чат и живые данные для второй строки. */
data class ChatHeaderInfo(
    val chat: Chat,
    /** Участники группы или подписчики канала, если сервер их назвал. */
    val participants: Int? = null,
    /** Когда собеседник был в сети (мс), 0 — неизвестно. */
    val lastSeenMs: Long = 0,
    /** Код присутствия собеседника (`PresenceStatus` ядра), `-1` — неизвестно. */
    val presence: Int = -1,
    /** Кто сейчас печатает, записывает или отправляет, по времени начала. */
    val typing: List<app.maxly.domain.Typist> = emptyList(),
    /** Бот с мини-приложением: его id для кнопки «Открыть приложение», иначе `null`. */
    val botAppId: String? = null,
    /** Своя отметка прочтения (мс, `participants[свой id]`): первое непрочитанное — новее неё. `0` — неизвестна. */
    val readMarkMs: Long = 0,
)

/**
 * Страница истории: время самого старого и самого нового пришедшего сообщения (мс) и сколько их.
 * [reachedOldest] — раньше сообщений нет, [reachedNewest] — страница дошла до свежих.
 */
data class HistorySpan(
    val oldestMs: Long,
    val newestMs: Long,
    val count: Int,
    val reachedOldest: Boolean = false,
    val reachedNewest: Boolean = false,
) {
    companion object {
        /** Пустая страница назад: история кончилась. */
        val START = HistorySpan(0, 0, 0, reachedOldest = true)
    }
}

/** История одного чата и действия над сообщениями. */
interface MessageRepository {
    /** Id своего аккаунта, `null` до входа. */
    val currentUserId: String?

    /**
     * Как можно удалить [messages] чата [chatId]: правила ядра ([DeletePlans]) — вид чата, свои
     * права в нём, `edit-timeout` сервера. Без стора ядра — [DeletePlans.withoutStore].
     */
    fun deletePlan(chatId: String, messages: List<Message>): app.maxly.domain.DeletePlan =
        DeletePlans.withoutStore(chatId, messages)

    /** Лента чата от старых к новым, вместе с ещё не ушедшими своими сообщениями. */
    fun messages(chatId: String): Flow<List<Message>>

    /** Шапка чата; `null`, пока чат не известен. */
    fun header(chatId: String): Flow<ChatHeaderInfo?>

    /** Свежая страница истории. Реализация может взять недавно полученную, не спрашивая сервер. */
    suspend fun loadLatest(chatId: String)

    /** Свежая страница истории в обход окна [loadLatest]: после своего действия (голос в опросе). */
    suspend fun refreshLatest(chatId: String) = loadLatest(chatId)

    /**
     * Свежая страница, когда пользователь открыл чат. В отличие от фоновых чтений, она не ждёт
     * паузы после `too.many.requests`: один запрос на открытие сервер выдерживает, а без него
     * экран пуст.
     */
    suspend fun openLatest(chatId: String) = loadLatest(chatId)

    /** Страница старше самого раннего сообщения. `false` — история кончилась. */
    suspend fun loadOlder(chatId: String): Boolean

    /**
     * [openLatest] с границами страницы. `null` — реализация границ не знает: лента показывает
     * всё, что есть (так устроены подмены в тестах).
     */
    suspend fun openLatestPage(chatId: String): HistorySpan? {
        openLatest(chatId)
        return null
    }

    /** Страница старше [beforeMs]. `null` — границы неизвестны. */
    suspend fun olderPage(chatId: String, beforeMs: Long): HistorySpan? = if (loadOlder(chatId)) null else HistorySpan.START

    /** Страница новее [afterMs]: окно перехода растёт к свежим. `null` — не умеет. */
    suspend fun newerPage(chatId: String, afterMs: Long): HistorySpan? = null

    /** Страница вокруг момента [timeMs]: переход к далёкому сообщению. `null` — не умеет. */
    suspend fun pageAround(chatId: String, timeMs: Long): HistorySpan? = null

    /** Сообщение по id, если его нет в ленте (нужно время для [pageAround]). */
    suspend fun findMessage(chatId: String, messageId: String): Message? = null

    /** Отправка текста. Сообщение сразу встаёт в ленту, при ошибке остаётся с пометкой. */
    suspend fun send(chatId: String, text: String, replyTo: String?)

    /**
     * Текст с отметками (смещения UTF-16): анимодзи, упоминания и разметка — жирный, курсив,
     * подчёркнутый, зачёркнутый, моноширинный, ссылки. Без отметок это обычная [send].
     * Реализация по умолчанию отметки не шлёт: так устроены подмены в тестах.
     */
    suspend fun sendFormatted(chatId: String, text: String, replyTo: String?, marks: List<app.maxly.domain.TextSpan>) {
        send(chatId, text, replyTo)
    }

    /**
     * Отправка вложений одним сообщением с подписью. Сообщение сразу встаёт в ленту;
     * [progress] получает долю загрузки 0…1.
     */
    suspend fun sendMedia(chatId: String, items: List<OutgoingFile>, caption: String, replyTo: String?, progress: (Float) -> Unit = {}): Unit =
        throw OrbitleError.Rejected("Отправка вложений недоступна")

    /** Отправить записанное голосовое. Сообщение сразу встаёт в ленту, как вложения. */
    suspend fun sendVoice(chatId: String, recording: app.maxly.domain.VoiceRecording, replyTo: String?): Unit =
        throw OrbitleError.Rejected("Голосовые недоступны")

    /** Отправить записанный кружок (`videoType` 1). Сообщение сразу встаёт в ленту. */
    suspend fun sendVideoNote(chatId: String, recording: app.maxly.domain.VideoNoteRecording, replyTo: String?): Unit =
        throw OrbitleError.Rejected("Видеосообщения недоступны")

    /** Отправить стикер каталога. */
    /**
     * Сигнал собеседникам, что пользователь [kind] (команда 65). Без ответа и без ограничения
     * частоты: её держит [app.maxly.presentation.chat.TypingSendPolicy]. `false` — сигнал не ушёл.
     */
    suspend fun sendTyping(chatId: String, kind: app.maxly.domain.TypingKind, postId: String? = null): Boolean = false

    suspend fun sendSticker(chatId: String, sticker: app.maxly.domain.Sticker, replyTo: String?): Unit =
        throw OrbitleError.Rejected("Стикеры недоступны")

    /** Повторить не ушедшее сообщение. */
    /** Остановить загрузку вложений своего сообщения [localId]: оно убирается, ничего не уходит. */
    fun cancelUpload(chatId: String, localId: String) = discard(chatId, localId)

    suspend fun retry(chatId: String, localId: String)

    /** Убрать не ушедшее сообщение из ленты. */
    fun discard(chatId: String, localId: String)

    suspend fun edit(chatId: String, messageId: String, text: String)

    /**
     * Правка с отметками, как у [sendFormatted]: сервер заменяет ими прежнюю разметку.
     * Реализация по умолчанию отметки не шлёт.
     */
    suspend fun editFormatted(chatId: String, messageId: String, text: String, marks: List<app.maxly.domain.TextSpan>) {
        edit(chatId, messageId, text)
    }

    suspend fun delete(chatId: String, messageIds: List<String>, forEveryone: Boolean)

    /**
     * Удалить выбранное одним запросом и узнать, что сервер удалить не смог
     * ([DeleteOutcome.failed]). По умолчанию — [delete], и удалённым считается всё.
     */
    suspend fun deleteMessages(chatId: String, messageIds: List<String>, forEveryone: Boolean): DeleteOutcome {
        delete(chatId, messageIds, forEveryone)
        return DeleteOutcome(messageIds, emptyList())
    }

    /** Отметить прочитанным всё до [messageId] включительно. */
    suspend fun markRead(chatId: String, messageId: String)

    /**
     * Чат снова непрочитан начиная с сообщения, отправленного в [fromMs]: сервер ставит отметку
     * прочтения перед ним. Видно и на других устройствах. Возвращает новое число непрочитанных.
     */
    suspend fun markUnread(chatId: String, fromMs: Long): Int =
        throw app.maxly.domain.OrbitleError.Rejected("Пометка непрочитанным недоступна")

    /** Поставить реакцию или снять свою (`null`). */
    suspend fun react(chatId: String, messageId: String, emoji: String?)

    /**
     * Реакции показанных сообщений (`MSG_GET_REACTIONS` 180), пачками до 100.
     * Пропуск id и пустая запись реакций не стирают: так сервер молчит, когда id не узнал.
     */
    suspend fun syncReactions(chatId: String, messageIds: List<String>) {}

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
    /**
     * «Кем прочитано» в группе, поставившие реакцию — первыми. `null` — сервер список не даёт
     * (не группа, звонок, участников больше `max-readmarks`).
     */
    suspend fun messageReaders(chatId: String, messageId: String): List<app.maxly.domain.MessageReader>? = null

    suspend fun reactionUsers(chatId: String, messageId: String): List<app.maxly.domain.ReactionUser> =
        throw OrbitleError.Rejected("Список недоступен")

    /** Пересылает сообщение [messageId] из [chatId] в чат [targetChatId]. */
    suspend fun forward(chatId: String, messageId: String, targetChatId: String): Unit = throw OrbitleError.Rejected("Пересылка недоступна")

    /**
     * Переслать несколько сообщений из [chatId] в [targetChatId] по порядку [messageIds] (от
     * старых к новым); первая ошибка останавливает остальные и возвращается в [ForwardOutcome.error].
     * По умолчанию — [forward] по одному.
     */
    suspend fun forwardMessages(chatId: String, messageIds: List<String>, targetChatId: String): ForwardOutcome {
        var sent = 0
        for (id in messageIds) {
            try {
                forward(chatId, id, targetChatId)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                return ForwardOutcome(sent, messageIds.size, e)
            }
            sent++
        }
        return ForwardOutcome(sent, messageIds.size, null)
    }

    /** Закрепить сообщение. `"0"` снимает закреп (`pinMessageId` 0). */
    suspend fun pin(chatId: String, messageId: String) {}

    /**
     * Закреплённые сообщения чата (`PINNED_MESSAGES_GET` 241), от нового к старому.
     * `null` — список недоступен: плашка берёт закреп из служебных сообщений истории.
     */
    suspend fun pinnedMessages(chatId: String): List<Message>? = null

    /**
     * Закрепить, открепить или открепить все (`PINNED_MESSAGE_UPDATE` 242). [forMe] — только у себя
     * (личный чат), [notify] `false` — без уведомления участникам. По умолчанию — старый одиночный
     * закреп [pin].
     */
    suspend fun updatePins(chatId: String, change: app.maxly.domain.PinChange, messageIds: List<String>, forMe: Boolean = false, notify: Boolean = true) {
        when (change) {
            app.maxly.domain.PinChange.PIN -> messageIds.firstOrNull()?.let { pin(chatId, it) }
            else -> pin(chatId, "0")
        }
    }

    /** Закрепы чата поменялись (пуш 243): плашка перечитывает список. */
    fun pinChanges(chatId: String): Flow<Unit> = emptyFlow()

    /** Своя реакция поменялась на другом устройстве (пуш 156): id сообщения. */
    fun ownReactionChanges(chatId: String): Flow<String> = emptyFlow()

    /**
     * Обновляет просроченные адреса фото чата (код 203), если сервер включил `photo-url-refresh`.
     * По умолчанию ничего не делает: так устроены подмены в тестах.
     */
    suspend fun refreshExpiredPhotos(chatId: String, nowMs: Long) {}


    /** Отложить текст до [sendAt] (мс). В обычную ленту оно не встаёт. [notify] `false` — без звука. */
    suspend fun schedule(chatId: String, text: String, sendAt: Long, notify: Boolean = true) {}

    /** Отложенные сообщения этого чата (`CHAT_HISTORY` 49, `DELAYED`), раньше уходящие — первыми. */
    suspend fun scheduled(chatId: String): List<app.maxly.domain.ScheduledMessage> = emptyList()

    /** Новый текст и время отложенного (`MSG_EDIT` 67). Вложения не трогаются. */
    suspend fun editScheduled(chatId: String, messageId: String, text: String, sendAt: Long): Unit =
        throw OrbitleError.Rejected("Правка отложенных недоступна")

    /** Отменить отложенные (`MSG_DELETE` 66, `DELAYED`). */
    suspend fun cancelScheduled(chatId: String, messageIds: List<String>): DeleteOutcome = DeleteOutcome(emptyList(), messageIds)

    /** Пуши отложенных этого чата (154). */
    fun scheduledChanges(chatId: String): Flow<app.maxly.domain.ScheduledChange> = emptyFlow()

    /** Опрос: вопрос и минимум два ответа. */
    suspend fun sendPoll(chatId: String, title: String, answers: List<String>) {}

    /** Голос (`SEND_VOTE` 304) за ответы [answerIds]; ответ — новые счётчики, если сервер их прислал. */
    suspend fun votePoll(chatId: String, messageId: String, pollId: String, answerIds: List<String>): app.maxly.domain.PollTally? = null

    /**
     * Свежее состояние опросов (`GET_POLL_UPDATES` 306): [polls] — пары id сообщения и `pollId`.
     * Ответ — по `pollId`. Пуша счётчиков нет, поэтому экран перезапрашивает сам.
     */
    suspend fun pollUpdates(chatId: String, polls: List<Pair<String, String>>): Map<String, PollContent> = emptyMap()

    /** Поиск по сообщениям открытого чата (`MSG_SEARCH` 73). */
    suspend fun searchInChat(chatId: String, query: String): List<app.maxly.domain.FoundMessage> = emptyList()

    suspend fun mediaLink(chatId: String, messageId: String, attachment: ChatAttachment): String = throw OrbitleError.Rejected("Вложение недоступно")
}

/** Итог удаления выбранного: [failed] — id, которые сервер оставил. */
data class DeleteOutcome(val deleted: List<String>, val failed: List<String>)

/** Итог пересылки выбранного: ушло [sent] из [total]; [error] — почему остановилась. */
data class ForwardOutcome(val sent: Int, val total: Int, val error: Throwable?) {
    val complete: Boolean get() = error == null && sent == total
}
