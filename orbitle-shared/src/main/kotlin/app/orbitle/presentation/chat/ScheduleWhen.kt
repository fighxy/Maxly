package app.orbitle.presentation.chat

import java.time.Instant
import java.time.ZoneId

/** Два пресета отложенной отправки. Часы подставляет экран, чтобы проверка не зависела от момента запуска. */
object ScheduleWhen {
    fun inOneHour(nowMs: Long): Long = nowMs + 3_600_000L

    /** 09:00 следующего календарного дня в [zone]. */
    fun tomorrowAtNine(nowMs: Long, zone: ZoneId): Long {
        val date = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate().plusDays(1)
        return date.atTime(9, 0).atZone(zone).toInstant().toEpochMilli()
    }
}
