package app.maxly.presentation.chat

import app.maxly.domain.TextSpan
import org.junit.Assert.assertEquals
import org.junit.Test

class AnimojiTextTest {
    private val catalog = mapOf("❤️" to "heart.json", "🔥" to "fire.json")

    @Test
    fun inlineUsesMarkUrlThenCatalog() {
        val text = "Привет 🔥 и ❤ и 😀"
        val spans = listOf(
            TextSpan(TextSpan.Kind.ANIMOJI, 7, 2, url = "own-fire.json", entityId = "1"),
            TextSpan(TextSpan.Kind.ANIMOJI, 12, 1, entityId = "2"),
            TextSpan(TextSpan.Kind.STRONG, 0, 6),
        )
        assertEquals(
            listOf(AnimojiText.Placed(7, 2, "🔥", "own-fire.json"), AnimojiText.Placed(12, 1, "❤", "heart.json")),
            AnimojiText.inline(text, spans, catalog),
        )
    }

    @Test
    fun inlineSkipsUnmarkedAndBrokenRanges() {
        val text = "🔥 огонь"
        assertEquals(emptyList<AnimojiText.Placed>(), AnimojiText.inline(text, emptyList(), catalog))
        val broken = listOf(TextSpan(TextSpan.Kind.ANIMOJI, 40, 2, entityId = "1"), TextSpan(TextSpan.Kind.ANIMOJI, 0, 2, entityId = "9"))
        assertEquals(listOf(AnimojiText.Placed(0, 2, "🔥", "fire.json")), AnimojiText.inline(text, broken, catalog))
    }

    @Test
    fun bigEmojiEachFromMarkOrCatalog() {
        val text = "🔥 ❤️ 😀"
        val spans = listOf(TextSpan(TextSpan.Kind.ANIMOJI, 0, 2, url = "own-fire.json", entityId = "1"))
        assertEquals(listOf("own-fire.json", "heart.json", null), AnimojiText.bigEmoji(text, listOf("🔥", "❤️", "😀"), spans, catalog))
    }

    @Test
    fun lookupIgnoresVariationSelector() {
        assertEquals("heart.json", AnimojiText.lookup(catalog, "❤"))
        assertEquals("heart.json", AnimojiText.lookup(mapOf("❤" to "heart.json"), "❤️"))
        assertEquals(null, AnimojiText.lookup(emptyMap(), "❤️"))
    }
}
