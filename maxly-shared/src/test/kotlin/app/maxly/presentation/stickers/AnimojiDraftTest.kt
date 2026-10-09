package app.maxly.presentation.stickers

import app.maxly.domain.AnimatedEmoji
import app.maxly.domain.TextSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AnimojiDraftTest {
    @Test
    fun spansUseUtf16Offsets() {
        val draft = AnimojiDraft()
        draft.insert(AnimatedEmoji(id = "5", emoji = "🔥", lottieUrl = "https://x/5.json"))
        val spans = draft.spans("ok 🔥 и 🔥")
        assertEquals(2, spans.size)
        assertEquals(TextSpan.Kind.ANIMOJI, spans[0].kind)
        assertEquals(3, spans[0].from)
        assertEquals(2, spans[0].length)
        assertEquals("5", spans[0].entityId)
        assertEquals("https://x/5.json", spans[0].url)
        assertEquals(8, spans[1].from)
        assertEquals(2, spans[1].length)
    }

    @Test
    fun longerEmojiWinsWhenItStartsTheSame() {
        val draft = AnimojiDraft()
        draft.insert(AnimatedEmoji(id = "1", emoji = "👍"))
        draft.insert(AnimatedEmoji(id = "2", emoji = "👍🏽", lottieUrl = "https://x/2.json"))
        val spans = draft.spans("👍🏽")
        assertEquals(1, spans.size)
        assertEquals(0, spans[0].from)
        assertEquals(4, spans[0].length)
        assertEquals("2", spans[0].entityId)
    }

    @Test
    fun clearDropsMarks() {
        val draft = AnimojiDraft()
        draft.insert(AnimatedEmoji(id = "5", emoji = "🔥"))
        draft.clear()
        assertTrue(draft.spans("🔥").isEmpty())
        draft.insert(AnimatedEmoji(id = "5", emoji = "🔥"))
        assertTrue(draft.spans("").isEmpty())
    }
}
