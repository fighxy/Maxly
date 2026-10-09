package app.maxly.presentation.stickers

import app.maxly.data.RecentStickerStore
import app.maxly.data.StickerRepository
import app.maxly.domain.AnimatedEmoji
import app.maxly.domain.Sticker
import app.maxly.domain.StickerCatalog
import app.maxly.domain.StickerSet
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MemoryRecents : RecentStickerStore {
    override var recentEmoji: List<String> = emptyList()
    override var recentStickers: List<Sticker> = emptyList()
}

private class FakeStickers : StickerRepository {
    var catalogCalls = 0
    var fail = false
    var animated = emptyList<AnimatedEmoji>()
    val asked = mutableListOf<List<String>>()
    override suspend fun animatedEmoji() = animated
    override suspend fun catalog(): StickerCatalog {
        catalogCalls++
        if (fail) throw IllegalStateException("нет сети")
        return StickerCatalog(listOf("9"), listOf(StickerSet("s1", "Коты", null, listOf("1", "2")), StickerSet("s2", "Пустой", null, emptyList())))
    }
    override suspend fun stickers(ids: List<String>): List<Sticker> {
        asked += ids
        return ids.map { Sticker(it, "https://st/$it.webp") }
    }
}

class StickerPanelTest {
    private val scope = TestScope(UnconfinedTestDispatcher())
    private val recents = MemoryRecents()
    private val repo = FakeStickers()

    @Test
    fun emojiCategoriesSkipUnsupported() {
        val panel = StickerPanel(repo, recents, scope, supported = { it != "😀" })
        panel.prepare()
        val people = panel.state.value.emoji.first()
        assertEquals("people", people.id)
        assertFalse("😀" in people.emoji)
        assertEquals(8, panel.state.value.emoji.size)
    }

    @Test
    fun recentEmojiComeFirstWithoutDuplicates() {
        val panel = StickerPanel(repo, recents, scope)
        panel.prepare()
        panel.usedEmoji("🔥")
        panel.usedEmoji("👍")
        panel.usedEmoji("🔥")
        val recent = panel.state.value.emoji.first()
        assertEquals(StickerPanel.RECENT_TITLE, recent.title)
        assertEquals(listOf("🔥", "👍"), recent.emoji)
        assertEquals(listOf("🔥", "👍"), recents.recentEmoji)
    }

    @Test
    fun catalogLoadsOnceAndDropsEmptySets() {
        val panel = StickerPanel(repo, recents, scope)
        panel.prepare()
        panel.prepare()
        assertEquals(1, repo.catalogCalls)
        assertEquals(listOf("recent", "s1"), panel.state.value.sections.map { it.id })
        // Первый раздел грузится сразу.
        assertEquals(listOf("9"), repo.asked.first())
        panel.load(panel.state.value.sections[1])
        panel.load(panel.state.value.sections[1])
        assertEquals(2, repo.asked.size)
        assertEquals("https://st/2.webp", panel.state.value.stickers["2"]?.url)
    }

    @Test
    fun usedStickerJoinsRecent() {
        val panel = StickerPanel(repo, recents, scope)
        panel.prepare()
        panel.usedSticker(Sticker("2", "u2"))
        assertEquals(listOf("2", "9"), panel.state.value.sections.first().stickerIds)
        assertEquals("2", recents.recentStickers.single().id)
    }

    @Test
    fun animatedSectionFollowsRecentsAndRemembersKey() {
        val fire = AnimatedEmoji(id = "3", emoji = "🔥", iconUrl = "https://i/3.png", lottieUrl = "https://a/3.json")
        repo.animated = listOf(fire)
        recents.recentEmoji = listOf("😀", "animoji:3", "animoji:missing")
        val panel = StickerPanel(repo, recents, scope)
        panel.prepare()
        assertEquals("3", panel.state.value.animated.single().id)
        val tabs = emojiTabs(panel.state.value)
        assertEquals(listOf("recent", "animated", "people"), tabs.map { it.id }.take(3))
        assertEquals(listOf("😀", "🔥"), tabs.first().picks.map { it.glyph })
        assertEquals("3", tabs.first().picks.last().animated?.id)
        assertEquals(StickerPanel.ANIMATED_TITLE, tabs[1].title)
        panel.usedAnimated(fire)
        assertEquals("animoji:3", recents.recentEmoji.first())
        assertEquals("animoji:3", panel.state.value.emoji.first().emoji.first())
    }

    @Test
    fun failedCatalogCanRetry() {
        repo.fail = true
        val panel = StickerPanel(repo, recents, scope)
        panel.prepare()
        assertEquals("Не удалось загрузить стикеры", panel.state.value.failure)
        assertFalse(panel.state.value.isLoading)
        repo.fail = false
        panel.prepare()
        assertEquals(2, repo.catalogCalls)
        assertTrue(panel.state.value.sections.isNotEmpty())
    }
}
