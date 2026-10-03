package app.orbitle.presentation.common

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Подписи «в сети» и «был(а)…» и русские множественные числа. */
class PresenceText(private val zone: ZoneId = ZoneId.systemDefault()) {

    fun status(online: Boolean, lastSeenMs: Long, nowMs: Long): String {
        if (online) return "в сети"
        if (lastSeenMs <= 0) return "был(а) недавно"
        val seconds = (nowMs - lastSeenMs) / 1000
        if (seconds in -59..59) return "был(а) только что"
        if (seconds in 1..3599) {
            val minutes = (seconds / 60).toInt()
            return "был(а) $minutes ${plural(minutes, "минуту", "минуты", "минут")} назад"
        }
        val date = Instant.ofEpochMilli(lastSeenMs).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val time = "%02d:%02d".format(date.hour, date.minute)
        val days = ChronoUnit.DAYS.between(date.toLocalDate(), now.toLocalDate())
        return when {
            days == 0L -> "был(а) в $time"
            days == 1L -> "был(а) вчера в $time"
            days > 0 && date.year == now.year -> "был(а) ${date.dayOfMonth} ${MONTHS_GENITIVE[date.monthValue - 1]}"
            else -> "был(а) %02d.%02d.%04d".format(date.dayOfMonth, date.monthValue, date.year)
        }
    }

    companion object {
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
