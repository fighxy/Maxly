package app.maxly.ui.chat

import app.maxly.presentation.chat.ReactionBurst
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReactionBurstHostTest {
    private val shown = mutableListOf<Long>()
    private val host = ReactionBurstHost { shown += it }

    @Test
    fun endsWhenBothTheGlyphAndTheEffectFinished() {
        host.update(ReactionBurst("m", "❤️", "body", "effect", 1))
        host.bodyFinished(1)
        assertEquals(emptyList<Long>(), shown)
        host.effectFinished(2)
        assertEquals(emptyList<Long>(), shown)
        host.effectFinished(1)
        assertEquals(listOf(1L), shown)
    }

    @Test
    fun onlyAnEffectOrOnlyTheGlyph() {
        host.update(ReactionBurst("m", "😂", null, "effect", 1))
        host.effectFinished(1)
        host.update(ReactionBurst("m", "🔥", "body", null, 2))
        host.bodyFinished(2)
        assertEquals(listOf(1L, 2L), shown)
    }

    @Test
    fun aNewBurstResetsTheAnchorAndTheOldOneExpiresSilently() {
        host.update(ReactionBurst("m", "❤️", "body", "effect", 1))
        host.anchor = androidx.compose.ui.geometry.Rect(0f, 0f, 10f, 10f)
        host.update(ReactionBurst("n", "👍", "body", "effect", 2))
        assertNull(host.anchor)
        host.expire(1)
        assertEquals(emptyList<Long>(), shown)
        host.expire(2)
        assertEquals(listOf(2L), shown)
        host.update(null)
        assertNull(host.burst)
    }
}
