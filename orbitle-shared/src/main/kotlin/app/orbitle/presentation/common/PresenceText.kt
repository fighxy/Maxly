package app.orbitle.presentation.common

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Подписи «в сети» и «был(а)…» и русские множественные числа. */
class PresenceText(private val zone: ZoneId = ZoneId.systemDefault()) {

    /**
     * «в сети» или «был(а)…». `null`, когда о присутствии ничего не известно ([lastSeenMs] `0`):
     * тогда строки нет вовсе, а не «был(а) недавно». Время из будущего (часы телефона отстают)
     * считается текущим.
     */
    fun status(online: Boolean, lastSeenMs: Long, nowMs: Long): String? {
        if (online) return "в сети"
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
            date.year == now.year -> "был(а) ${date.dayOfMonth} ${MONTHS_GENITIVE[date.monthValue - 1]}"
            else -> "был(а) %02d.%02d.%04d".format(date.dayOfMonth, date.monthValue, date.year)
        }
    }

    /**
     * Когда подпись [status] сменится сама: следующая минута в первый час, потом полночь
     * («в 14:00» → «вчера в 14:00» → дата). `null` — не сменится (в сети, ничего не известно,
     * или уже дата).
     */
    fun nextChange(online: Boolean, lastSeenMs: Long, nowMs: Long): Long? {
        if (online || lastSeenMs <= 0) return null
        val seen = minOf(lastSeenMs, nowMs)
        val elapsed = nowMs - seen
        if (elapsed < HOUR_MS) return seen + (elapsed / MINUTE_MS + 1) * MINUTE_MS
        val date = Instant.ofEpochMilli(seen).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val days = ChronoUnit.DAYS.between(date.toLocalDate(), now.toLocalDate())
        if (days > 1) return null
        return now.toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    }

    companion object {
        private const val MINUTE_MS = 60_000L
        private const val HOUR_MS = 3_600_000L

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
