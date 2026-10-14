package app.maxly.data

import app.maxly.data.diagnostics.AppLog
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout

/** Обновление не уложилось в отведённое время. Обычная ошибка, не отмена. */
class RefreshTimeoutException(timeoutMs: Long) : Exception("обновление дольше $timeoutMs мс")

/**
 * Одно обновление за раз и с пределом по времени: зависший запрос не держит замок навсегда.
 * В журнал пишутся начало, конец, пропуск и длительность; без идентификаторов и содержимого.
 */
class RefreshGate(
    private val name: String,
    private val timeoutMs: Long = DEFAULT_TIMEOUT_MS,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val lock = Mutex()

    val isBusy: Boolean get() = lock.isLocked

    /** `false` — обновление уже идёт и этот вызов пропущен. */
    suspend fun run(block: suspend () -> Unit): Boolean {
        if (lock.isLocked) {
            AppLog.i(TAG, "$name: пропуск, уже идёт")
            return false
        }
        lock.withLock {
            val start = clock()
            AppLog.i(TAG, "$name: начало")
            var result = "error"
            try {
                withTimeout(timeoutMs) { block() }
                result = "ok"
            } catch (e: TimeoutCancellationException) {
                result = "timeout"
                throw RefreshTimeoutException(timeoutMs)
            } finally {
                AppLog.i(TAG, "$name: конец, $result, ${clock() - start} мс")
            }
        }
        return true
    }

    companion object {
        const val DEFAULT_TIMEOUT_MS = 30_000L
        private const val TAG = "refresh"
    }
}

/**
 * Пользователи, уже запрошенные у сервера. Запрос, который не удался, снимает отметку,
 * чтобы следующее обновление спросило их снова.
 */
class UserRequests {
    private val requested = mutableSetOf<Long>()

    /** Из [ids] те, что ещё не запрошены; они сразу отмечаются запрошенными. */
    @Synchronized fun claim(ids: Collection<Long>): List<Long> = ids.filter { requested.add(it) }

    @Synchronized fun release(ids: Collection<Long>) { requested.removeAll(ids.toSet()) }

    @Synchronized fun clear() = requested.clear()

    @Synchronized fun isRequested(id: Long): Boolean = id in requested

    /** Загрузить [wanted] порциями по [chunk]: порция с ошибкой снова в очереди. */
    suspend fun load(wanted: Collection<Long>, chunk: Int = 100, loader: suspend (List<Long>) -> Unit) {
        val fresh = claim(wanted)
        for (part in fresh.chunked(chunk)) {
            try {
                loader(part)
            } catch (e: kotlinx.coroutines.CancellationException) {
                release(part)
                throw e
            } catch (e: Exception) {
                release(part)
                AppLog.w("refresh", "пользователи: порция ${part.size} не загрузилась, повтор позже (${e.javaClass.simpleName})")
            }
        }
    }
}
