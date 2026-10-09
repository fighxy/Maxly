package app.maxly.data

import app.maxly.domain.OrbitleError

/**
 * Пауза после ответа сервера `too.many.requests`.
 *
 * Сервер Max отказывает так, когда клиент читает слишком часто (история, комментарии, общие
 * медиа, карточки чатов). Каждый новый запрос в это время только продлевает отказ, поэтому
 * чтения через [MaxCoreGateway.read] на паузу на сервер не уходят, а сразу получают тот же
 * отказ. Пауза растёт с каждым отказом подряд (15, 30, 60, 120 с) и сбрасывается удачным
 * чтением. Отправку, отметки прочтения и вход пауза не трогает: они идут через `call`.
 */
class ServerRateLimit(private val clock: () -> Long = System::currentTimeMillis) {
    private var until = 0L
    private var strikes = 0

    /** Сколько миллисекунд ещё ждать. `null` — можно спрашивать сервер. */
    @Synchronized
    fun remainingMs(): Long? {
        val left = until - clock()
        return left.takeIf { it > 0 }
    }

    /** Сервер ответил `too.many.requests`. */
    @Synchronized
    fun noteLimited() {
        val pause = PAUSES_MS[minOf(strikes, PAUSES_MS.lastIndex)]
        strikes += 1
        until = maxOf(until, clock() + pause)
    }

    /** Чтение прошло: следующий отказ снова начнёт с короткой паузы. */
    @Synchronized
    fun noteSuccess() {
        strikes = 0
    }

    companion object {
        /** Ключ ошибки сервера, по которому включается пауза. */
        const val KEY = OrbitleError.RATE_LIMIT_CODE
        private val PAUSES_MS = longArrayOf(15_000, 30_000, 60_000, 120_000)

        /** Одна пауза на процесс: сервер считает запросы всей сессии. */
        val shared = ServerRateLimit()

        fun isLimit(key: String?): Boolean = key == KEY
    }
}
