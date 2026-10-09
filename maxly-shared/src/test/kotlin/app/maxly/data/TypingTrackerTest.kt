package app.maxly.data

import app.maxly.domain.Typist
import app.maxly.domain.TypingKind
import com.maxly.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Test

class TypingTrackerTest {
    private fun state(typing: Map<Long, Long>, types: Map<Long, String> = emptyMap()) =
        MaxState(me = 1, typing = mapOf(10L to typing), typingTypes = mapOf(10L to types))

    @Test
    fun keepsStartOrderWhileSignalsRepeat() {
        val tracker = TypingTracker()
        val names = mapOf(2L to "Анна", 3L to "Пётр")
        val first = tracker.typists(state(mapOf(1L to 0, 2L to 1_000, 3L to 2_000), mapOf(3L to "AUDIO")), 10, 2_000) { names[it] }
        assertEquals(listOf(Typist("Анна", TypingKind.TEXT, 1_000, "2"), Typist("Пётр", TypingKind.AUDIO, 2_000, "3")), first)
        // Анна повторила сигнал позже Петра, но начала раньше.
        val later = tracker.typists(state(mapOf(2L to 7_500, 3L to 2_000), mapOf(3L to "AUDIO")), 10, 8_000) { names[it] }
        assertEquals(listOf("Анна", "Пётр"), later.map { it.name })
        assertEquals(1_000L, later.first().sinceMs)
    }

    @Test
    fun signalAfterExpiryStartsAgainEvenUnobserved() {
        val tracker = TypingTracker()
        tracker.typists(state(mapOf(2L to 0, 3L to 1_000)), 10, 1_000) { null }
        // Между запросами отметка Анны истекла и пришла новая: она встаёт за Петром.
        val again = tracker.typists(state(mapOf(2L to 9_000, 3L to 8_500)), 10, 9_000) { null }
        assertEquals(listOf("3", "2"), again.map { it.userId })
    }

    @Test
    fun forgetsStartOnceSignalExpires() {
        val tracker = TypingTracker()
        tracker.typists(state(mapOf(2L to 0)), 10, 0) { null }
        assertEquals(emptyList<Typist>(), tracker.typists(state(mapOf(2L to 0)), 10, 9_000) { null })
        assertEquals(20_000L, tracker.typists(state(mapOf(2L to 20_000)), 10, 20_000) { null }.single().sinceMs)
    }
}
