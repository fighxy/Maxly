package app.maxly.presentation.chat

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Пресеты и ручной выбор времени отложенной отправки. Часы подставляет экран, чтобы проверка не зависела от момента запуска. */
object ScheduleWhen {
    fun inOneHour(nowMs: Long): Long = nowMs + 3_600_000L

    /** 09:00 следующего календарного дня в [zone]. */
    fun tomorrowAtNine(nowMs: Long, zone: ZoneId): Long {
        val date = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate().plusDays(1)
        return date.atTime(9, 0).atZone(zone).toInstant().toEpochMilli()
    }

    /** Дни для ручного выбора: сегодня и следующие, всего [count]. */
    fun days(nowMs: Long, zone: ZoneId, count: Int = 7): List<LocalDate> {
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        return List(count) { today.plusDays(it.toLong()) }
    }

    fun dayLabel(day: LocalDate, today: LocalDate): String = when (day) {
        today -> "Сегодня"
        today.plusDays(1) -> "Завтра"
        else -> "%02d.%02d".format(day.dayOfMonth, day.monthValue)
    }

    fun at(day: LocalDate, hour: Int, minute: Int, zone: ZoneId): Long =
        day.atTime(hour.coerceIn(0, 23), minute.coerceIn(0, 59)).atZone(zone).toInstant().toEpochMilli()

    /** Начальный выбор: [baseMs] (или через час), минуты вверх до кратных пяти. */
    fun initial(baseMs: Long?, nowMs: Long, zone: ZoneId): ScheduleChoice {
        val start = Instant.ofEpochMilli(baseMs?.takeIf { it > nowMs } ?: inOneHour(nowMs)).atZone(zone)
        val rounded = if (baseMs != null && baseMs > nowMs) start else start.plusMinutes(((5 - start.minute % 5) % 5).toLong())
        return ScheduleChoice(rounded.toLocalDate(), rounded.hour, rounded.minute)
    }

    /** Сдвиг часов и минут по кругу. */
    fun shift(choice: ScheduleChoice, hours: Int = 0, minutes: Int = 0): ScheduleChoice =
        choice.copy(hour = Math.floorMod(choice.hour + hours, 24), minute = Math.floorMod(choice.minute + minutes, 60))
}

/** Ручной выбор: день, час и минута. */
data class ScheduleChoice(val day: LocalDate, val hour: Int, val minute: Int) {
    fun toMillis(zone: ZoneId): Long = ScheduleWhen.at(day, hour, minute, zone)
    val clock: String get() = "%02d:%02d".format(hour, minute)
}
