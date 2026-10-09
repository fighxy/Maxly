package app.maxly.data

import com.max.core.api.PresenceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PresenceTimeTest {
    @Test
    fun serverSecondsBecomeMilliseconds() {
        assertEquals(1_790_683_200_000L, PresenceTime.ms(1_790_683_200L))
        // Уже миллисекунды — без второго умножения.
        assertEquals(1_790_683_200_000L, PresenceTime.ms(1_790_683_200_000L))
        assertEquals(0L, PresenceTime.ms(null))
        assertEquals(0L, PresenceTime.ms(0))
        assertEquals(0L, PresenceTime.ms(-5))
    }

    @Test
    fun onlineOnlyByStatusOne() {
        assertTrue(PresenceTime.isOnline(PresenceInfo(null, 1)))
        assertFalse(PresenceTime.isOnline(PresenceInfo(1_790_683_200L, null)))
        assertFalse(PresenceTime.isOnline(PresenceInfo(1_790_683_200L, 0)))
        assertFalse(PresenceTime.isOnline(null))
    }

    @Test
    fun pageEntryAndFreshest() {
        assertEquals(PresenceInfo(1_790_683_200L, 1), PresenceTime.from(mapOf("seen" to 1_790_683_200, "status" to 1)))
        assertEquals(PresenceInfo(null, null), PresenceTime.from(emptyMap<String, Any>()))
        assertNull(PresenceTime.from(null))
        val stored = PresenceInfo(1_790_683_200L, 1)
        val older = PresenceInfo(1_790_683_100L, null)
        val newer = PresenceInfo(1_790_683_300L, null)
        assertEquals(stored, PresenceTime.freshest(stored, older))
        assertEquals(newer, PresenceTime.freshest(stored, newer))
        assertEquals(older, PresenceTime.freshest(null, older))
        assertEquals(stored, PresenceTime.freshest(stored, null))
    }
}
