package app.orbitle.diagnostics

/**
 * Сторож потока окна (AWT EDT). Раз в [intervalMs] кладёт в очередь окна пустую задачу и ждёт,
 * когда она выполнится:
 * - выполнилась позже [slowMs] — [onSlow], окно подтормозило;
 * - не выполнилась за [hangMs] — один раз [onHang]: окно зависло, пора снять стеки потоков;
 * - выполнилась после зависания — [onRecovered], окно ожило.
 *
 * Если между тактами прошло больше трёх интервалов, компьютер спал или процесс стоял целиком:
 * текущая проба забывается, чтобы сон не выглядел зависанием.
 *
 * Логика без потоков и часов: такт — [tick], проба — [post]. Поток сторожа даёт [start].
 */
class UiWatchdog(
    private val post: (Runnable) -> Unit,
    private val now: () -> Long,
    private val intervalMs: Long = INTERVAL_MS,
    private val slowMs: Long = SLOW_MS,
    private val hangMs: Long = HANG_MS,
    private val onSlow: (waitedMs: Long) -> Unit = {},
    private val onHang: (waitedMs: Long) -> Unit = {},
    private val onRecovered: (waitedMs: Long) -> Unit = {},
) {
    private val lock = Any()
    private var probe = 0L
    private var sentAt = -1L
    private var lastTick = -1L
    private var hung = false

    /** Такт сторожа: отправить пробу или проверить, не застряла ли отправленная. */
    fun tick() {
        val time = now()
        var hangFor = -1L
        val send: Long
        synchronized(lock) {
            val asleep = lastTick >= 0 && time - lastTick > intervalMs * 3
            lastTick = time
            if (asleep && !hung) sentAt = -1
            if (sentAt >= 0) {
                val waited = time - sentAt
                if (!hung && waited >= hangMs) {
                    hung = true
                    hangFor = waited
                }
                send = -1
            } else {
                sentAt = time
                send = ++probe
            }
        }
        if (hangFor >= 0) onHang(hangFor)
        if (send >= 0) post(Runnable { answered(send) })
    }

    private fun answered(id: Long) {
        val time = now()
        val waited: Long
        val recovered: Boolean
        synchronized(lock) {
            if (id != probe || sentAt < 0) return
            waited = time - sentAt
            recovered = hung
            hung = false
            sentAt = -1
        }
        when {
            recovered -> onRecovered(waited)
            waited >= slowMs -> onSlow(waited)
        }
    }

    /** Поток-демон, который вызывает [tick] раз в [intervalMs]. */
    fun start(): Thread = Thread({
        while (!Thread.currentThread().isInterrupted) {
            try {
                Thread.sleep(intervalMs)
                tick()
            } catch (_: InterruptedException) {
                return@Thread
            } catch (_: Throwable) {
                // Сторож не должен умирать от ошибки в журнале.
            }
        }
    }, "orbitle-ui-watchdog").apply {
        isDaemon = true
        start()
    }

    companion object {
        const val INTERVAL_MS = 500L
        const val SLOW_MS = 1_000L
        const val HANG_MS = 5_000L
    }
}
