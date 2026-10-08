package app.orbitle.presentation.chat

import app.orbitle.data.DraftRepository
import app.orbitle.data.ServerDrafts
import app.orbitle.domain.ChatDraft
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Отправка черновиков на сервер. Правки поля копятся [delayMs] и уходят одним сохранением;
 * уход из чата ([flush]) отправляет сразу. Пустой черновик — `discard`; после отправки сообщения
 * черновик сервера стирает ядро ([sent]). Живёт дольше экрана
 * чата ([scope] приложения), чтобы последний черновик ушёл и после закрытия.
 *
 * Ошибки не показываются: копия на устройстве остаётся, следующая правка повторит отправку.
 */
class DraftSync(
    private val scope: CoroutineScope,
    private val remote: DraftRepository,
    private val delayMs: Long = DELAY_MS,
) {
    private val lock = Any()
    private val waiting = mutableMapOf<String, Job>()
    private val wanted = mutableMapOf<String, ChatDraft?>()
    /** Сохранения и удаления по очереди: удаление не обгонит сохранение того же чата. */
    private val order = Mutex()

    /** Черновики сервера по чатам и выбор между ними и черновиком устройства. */
    val serverDrafts: ServerDrafts get() = remote

    fun server(chatId: String): ChatDraft? = remote.current(chatId)

    /** Что показать в поле ввода [chatId] при черновике устройства [local] ([ServerDrafts.reconcile]). */
    fun reconcile(chatId: String, local: ChatDraft?): ChatDraft? = remote.reconcile(chatId, local)

    /** Поле ввода [chatId] стало таким; `null` или ни текста, ни ответа — черновика больше нет. */
    fun changed(chatId: String, draft: ChatDraft?) {
        synchronized(lock) {
            wanted[chatId] = draft?.takeIf { !it.isEmpty }
            waiting.remove(chatId)?.cancel()
            waiting[chatId] = scope.launch {
                delay(delayMs)
                push(chatId)
            }
        }
    }

    /** Отправить отложенное сейчас (уход из чата). */
    fun flush(chatId: String) {
        synchronized(lock) {
            if (!wanted.containsKey(chatId)) return
            waiting.remove(chatId)?.cancel()
            waiting[chatId] = scope.launch { push(chatId) }
        }
    }

    /**
     * Сообщение ушло: отложенное сохранение черновика [chatId] отменяется, чтобы не вернуть на
     * сервер уже отправленный текст. Сам черновик сервера стирает ядро (`DRAFT_DISCARD` после
     * отправки, правило `test-fixtures/drafts`): отсюда запроса нет.
     */
    fun sent(chatId: String) {
        synchronized(lock) {
            waiting.remove(chatId)?.cancel()
            wanted.remove(chatId)
        }
    }

    private suspend fun push(chatId: String) {
        val draft = synchronized(lock) {
            if (!wanted.containsKey(chatId)) return
            waiting.remove(chatId)
            wanted.remove(chatId)
        }
        order.withLock {
            try {
                val current = remote.current(chatId)
                when {
                    draft == null -> if (current != null) remote.discard(chatId)
                    draft.sameContent(current) -> Unit
                    else -> remote.save(chatId, draft)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Черновик остаётся на устройстве.
            }
        }
    }

    companion object {
        /** Пауза после последней правки поля. */
        const val DELAY_MS = 1_750L
    }
}
