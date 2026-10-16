package app.maxly.data.gifka

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Очередь pingback: события копятся и уходят пачкой через [delayMs] (или сразу при [maxBatch]).
 * Ничего не ждёт и не бросает: ошибка сети — события просто теряются. Показ одного медиа
 * считается один раз за жизнь очереди (панель открыта).
 */
class GifkaPingback(
    private val api: GifkaApi,
    private val scope: CoroutineScope,
    private val delayMs: Long = 2_000,
    private val maxBatch: Int = 50,
) {
    private val queue = mutableListOf<GifkaEvent>()
    private val viewed = HashSet<String>()
    private var timer: Job? = null

    fun views(ids: List<String>) = synchronized(this) {
        ids.filter { viewed.add(it) }.forEach { queue += GifkaEvent(it, GifkaEvent.Kind.VIEW) }
        schedule()
    }

    fun click(id: String) = add(GifkaEvent(id, GifkaEvent.Kind.CLICK))
    fun send(id: String) = add(GifkaEvent(id, GifkaEvent.Kind.SEND))

    private fun add(event: GifkaEvent) = synchronized(this) {
        queue += event
        schedule()
    }

    private fun schedule() {
        if (queue.isEmpty()) return
        if (queue.size >= maxBatch) {
            timer?.cancel()
            timer = null
            flushNow()
            return
        }
        if (timer?.isActive == true) return
        timer = scope.launch {
            delay(delayMs)
            synchronized(this@GifkaPingback) { timer = null; flushNow() }
        }
    }

    private fun flushNow() {
        val batch = queue.toList()
        queue.clear()
        batch.chunked(maxBatch).forEach { chunk ->
            scope.launch {
                try {
                    api.pingback(chunk)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // pingback необязателен для работы панели.
                }
            }
        }
    }
}
