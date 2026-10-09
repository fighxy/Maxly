package app.maxly.presentation.chat

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class ScheduleWhenTest {
    @Test
    fun presetsAreStable() {
        val now = Instant.parse("2026-10-03T15:00:00Z").toEpochMilli()
        assertEquals(now + 3_600_000L, ScheduleWhen.inOneHour(now))
        val zone = ZoneId.of("UTC")
        assertEquals(Instant.parse("2026-10-04T09:00:00Z").toEpochMilli(), ScheduleWhen.tomorrowAtNine(now, zone))
    }

    @Test
    fun manualChoiceRoundsUpAndWraps() {
        val zone = java.time.ZoneId.of("Asia/Novosibirsk")
        // 2026-10-09 07:42 +07 → через час 08:42 → 08:45.
        val now = java.time.ZonedDateTime.of(2026, 10, 9, 7, 42, 10, 0, zone).toInstant().toEpochMilli()
        val choice = ScheduleWhen.initial(null, now, zone)
        assertEquals("08:45", choice.clock)
        assertEquals(java.time.LocalDate.of(2026, 10, 9), choice.day)
        assertEquals("23:45", ScheduleWhen.shift(choice, hours = -9).clock)
        assertEquals("08:05", ScheduleWhen.shift(choice, minutes = 20).clock)
        val at = choice.toMillis(zone)
        assertEquals(java.time.ZonedDateTime.of(2026, 10, 9, 8, 45, 0, 0, zone).toInstant().toEpochMilli(), at)
        assertEquals(choice, ScheduleWhen.initial(at, now, zone))
    }

    @Test
    fun dayLabelsAndRange() {
        val zone = java.time.ZoneId.of("Asia/Novosibirsk")
        val now = java.time.ZonedDateTime.of(2026, 10, 9, 23, 30, 0, 0, zone).toInstant().toEpochMilli()
        val days = ScheduleWhen.days(now, zone)
        assertEquals(7, days.size)
        assertEquals(listOf("Сегодня", "Завтра", "11.10"), days.take(3).map { ScheduleWhen.dayLabel(it, days.first()) })
    }
}
