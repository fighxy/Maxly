package app.orbitle.presentation.common

import com.max.core.api.PresenceStatus
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Подписи «в сети» и «был(а)…» и русские множественные числа. */
class PresenceText(private val zone: ZoneId = ZoneId.systemDefault()) {

    /**
     * «в сети» или «был(а)…» по коду [presence] ([PresenceStatus]) и времени [lastSeenMs]:
     * `1` — «в сети», `2` — «был(а) недавно», `3` — «был(а) давно» (время скрыто, не смотрится),
     * `0` и `-1` — по времени; другой код — «недавно», как у ядра. `null`, когда времени нет и код
     * ничего не говорит: строки нет вовсе. [online] главнее кода (запись «в сети» из той же
     * записи присутствия). Время из будущего (часы телефона отстают) считается текущим.
     */
    fun status(online: Boolean, lastSeenMs: Long, nowMs: Long, presence: Int = PresenceStatus.UNKNOWN): String? {
        when (code(online, presence)) {
            PresenceStatus.ONLINE -> return "в сети"
            PresenceStatus.RECENTLY -> return "был(а) недавно"
            PresenceStatus.LONG_AGO -> return "был(а) давно"
        }
        if (lastSeenMs <= 0) return null
        val seen = minOf(lastSeenMs, nowMs)
        val seconds = (nowMs - seen) / 1000
        if (seconds < 60) return "был(а) только что"
        if (seconds < 3600) {
            val minutes = (seconds / 60).toInt()
            return "был(а) $minutes ${plural(minutes, "минуту", "минуты", "минут")} назад"
        }
        val date = Instant.ofEpochMilli(seen).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val time = "%02d:%02d".format(date.hour, date.minute)
        val days = ChronoUnit.DAYS.between(date.toLocalDate(), now.toLocalDate())
        return when {
            days == 0L -> "был(а) в $time"
            days == 1L -> "был(а) вчера в $time"
            date.year == now.year -> "был(а) ${date.dayOfMonth} ${MONTHS_SHORT[date.monthValue - 1]}"
            else -> "был(а) %02d.%02d.%04d".format(date.dayOfMonth, date.monthValue, date.year)
        }
    }

    /**
     * Когда подпись [status] сменится сама: следующая минута в первый час, потом полночь
     * («в 14:00» → «вчера в 14:00» → дата). `null` — не сменится (в сети, «недавно», «давно»,
     * ничего не известно, или уже дата).
     */
    fun nextChange(online: Boolean, lastSeenMs: Long, nowMs: Long, presence: Int = PresenceStatus.UNKNOWN): Long? {
        val code = code(online, presence)
        if (code != PresenceStatus.OFFLINE && code != PresenceStatus.UNKNOWN) return null
        if (lastSeenMs <= 0) return null
        val seen = minOf(lastSeenMs, nowMs)
        val elapsed = nowMs - seen
        if (elapsed < HOUR_MS) return seen + (elapsed / MINUTE_MS + 1) * MINUTE_MS
        val date = Instant.ofEpochMilli(seen).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val days = ChronoUnit.DAYS.between(date.toLocalDate(), now.toLocalDate())
        if (days > 1) return null
        return now.toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    }

    /** Код для подписи: «в сети» по [online], иначе [presence], неизвестный код — «недавно». */
    private fun code(online: Boolean, presence: Int): Int = when {
        online -> PresenceStatus.ONLINE
        presence in PresenceStatus.UNKNOWN..PresenceStatus.LONG_AGO -> presence
        else -> PresenceStatus.RECENTLY
    }

    companion object {
        private const val MINUTE_MS = 60_000L
        private const val HOUR_MS = 3_600_000L

        /** Месяц в подписи «был(а) 27 сен»: май в родительном, остальные сокращены. */
        val MONTHS_SHORT = listOf("янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек")

        val MONTHS_GENITIVE = listOf(
            "января", "февраля", "марта", "апреля", "мая", "июня",
            "июля", "августа", "сентября", "октября", "ноября", "декабря",
        )

        /** 1 участник, 2 участника, 5 участников, 11 участников. */
        fun plural(count: Int, one: String, few: String, many: String): String {
            val tens = count % 100
            val units = count % 10
            return when {
                tens in 11..14 -> many
                units == 1 -> one
                units in 2..4 -> few
                else -> many
            }
        }

        /** `12500` → `12 500` (узкий неразрывный пробел). */
        fun grouped(count: Int): String {
            val digits = count.toString()
            if (digits.length <= 4) return digits
            return digits.reversed().chunked(3).joinToString("\u202F").reversed()
        }
    }
}
