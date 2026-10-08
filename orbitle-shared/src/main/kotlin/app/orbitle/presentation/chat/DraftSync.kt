package app.orbitle.presentation.chat

import app.orbitle.data.DraftRepository
import app.orbitle.domain.ChatDraft
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Отправка черновиков на сервер. Правки поля копятся [delayMs] и уходят одним сохранением;
 * уход из чата ([flush]) отправляет сразу. Пустой черновик — `discard`. Живёт дольше экрана
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

    /** Черновики сервера по чатам. */
    val serverDrafts: Flow<Map<String, ChatDraft>> get() = remote.drafts

    fun server(chatId: String): ChatDraft? = remote.current(chatId)

    /** Поле ввода [chatId] стало таким; `null` или пустой текст — черновика больше нет. */
    fun changed(chatId: String, draft: ChatDraft?) {
        synchronized(lock) {
            wanted[chatId] = draft?.takeIf { it.text.isNotBlank() }
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

    /** Сообщение ушло: черновик убрать сразу. */
    fun sent(chatId: String) {
        changed(chatId, null)
        flush(chatId)
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
