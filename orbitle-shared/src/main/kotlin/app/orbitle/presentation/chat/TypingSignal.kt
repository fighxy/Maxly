package app.orbitle.presentation.chat

import app.orbitle.domain.TypingKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Сигналы «печатает…» и родни для одного чата (команда 65). Ядро частоту не ограничивает, поэтому
 * здесь: не чаще раза в [intervalMs], один счётчик на все виды действия. Долгие действия (запись,
 * загрузка) повторяют сигнал, пока не закончатся: у собеседника он живёт 8 с.
 */
class TypingSignal(
    private val scope: CoroutineScope,
    private val clock: () -> Long,
    private val intervalMs: Long = INTERVAL_MS,
    private val tickMs: Long = TICK_MS,
    private val send: suspend (TypingKind) -> Unit,
) {
    private var lastAt: Long? = null
    private val activities = LinkedHashMap<Any, TypingKind>()
    private var ticker: Job? = null

    /** Пользователь что-то сделал: сигнал уходит, если с прошлого прошло [intervalMs]. */
    fun ping(kind: TypingKind) {
        val now = clock()
        lastAt?.let { if (now - it < intervalMs) return }
        lastAt = now
        scope.launch {
            try {
                send(kind)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Сигнал необязателен: следующий уйдёт с очередным действием.
            }
        }
    }

    /** Началось долгое действие [key]: сигнал сразу и повторно, пока не позовут [end]. Повторяется самое свежее. */
    fun begin(key: Any, kind: TypingKind) {
        activities.remove(key)
        activities[key] = kind
        ping(kind)
        if (ticker?.isActive == true) return
        ticker = scope.launch {
            while (true) {
                delay(tickMs)
                val current = activities.values.lastOrNull() ?: break
                ping(current)
            }
        }
    }

    fun end(key: Any) {
        activities.remove(key) ?: return
        if (activities.isEmpty()) {
            ticker?.cancel()
            ticker = null
        }
    }

    companion object {
        /** Не чаще раза в 6 с на чат: так договорились клиенты, у собеседника сигнал живёт 8 с. */
        const val INTERVAL_MS = 6_000L
        private const val TICK_MS = 1_000L
    }
}
