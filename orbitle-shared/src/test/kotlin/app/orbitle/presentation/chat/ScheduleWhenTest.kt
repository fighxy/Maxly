package app.orbitle.presentation.chat

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
}
