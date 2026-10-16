package app.maxly.presentation.gifs

import app.maxly.data.gifka.GifkaApi
import app.maxly.data.gifka.GifkaError
import app.maxly.data.gifka.GifkaEvent
import app.maxly.data.gifka.GifkaReportReason
import app.maxly.domain.GifkaMedia
import app.maxly.domain.GifkaPage
import app.maxly.domain.GifkaType
import app.maxly.domain.OutgoingFile
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

@OptIn(ExperimentalCoroutinesApi::class)
class GifSearchModelTest {
    private fun media(id: String) = GifkaMedia(id, GifkaType.GIF, id, 10, 20, null, "https://x/$id.webp", null, null)

    private class FakeApi : GifkaApi {
        val queries = mutableListOf<String>()
        var fail: Exception? = null
        override suspend fun search(query: String, type: GifkaType, limit: Int, offset: Int): GifkaPage {
            queries += query; fail?.let { throw it }
            return GifkaPage(listOf(GifkaMedia(query, type, query, 1, 1, null, "u", null, null)), 1)
        }
        override suspend fun trending(type: GifkaType, limit: Int, offset: Int): GifkaPage {
            queries += "<trending>"; fail?.let { throw it }
            return GifkaPage(listOf(GifkaMedia("t", type, "t", 1, 1, null, "u", null, null)), null)
        }
        override suspend fun downloadGif(media: GifkaMedia, target: File): File {
            target.parentFile.mkdirs(); target.writeBytes("GIF89a".toByteArray()); return target
        }
        val events = mutableListOf<GifkaEvent>()
        val reports = mutableListOf<Pair<String, GifkaReportReason>>()
        override suspend fun pingback(events: List<GifkaEvent>) { this.events += events }
        override suspend fun report(mediaId: String, reason: GifkaReportReason, details: String?) { reports += mediaId to reason }
    }

    private val dir = Files.createTempDirectory("gifs").toFile()

    @Test
    fun trendingWhenEmptyAndDebouncedSearch() = runTest {
        val api = FakeApi()
        val model = GifSearchModel(api, backgroundScope, { dir }, canSend = true)
        model.open(); runCurrent()
        assertEquals(listOf("<trending>"), api.queries)
        model.onQuery("к"); advanceTimeBy(100)
        model.onQuery("ко"); advanceTimeBy(100)
        model.onQuery("кот"); advanceTimeBy(500); runCurrent()
        assertEquals(listOf("<trending>", "кот"), api.queries)
        assertEquals("кот", model.state.value.items.single().id)
        model.onQuery(""); runCurrent()
        assertEquals("t", model.state.value.items.single().id)
    }

    @Test
    fun rateLimitShowsMessage() = runTest {
        val api = FakeApi().apply { fail = GifkaError.RateLimited(10) }
        val model = GifSearchModel(api, backgroundScope, { dir }, canSend = true)
        model.open(); runCurrent()
        assertEquals("Слишком много запросов к gifka.me, попробуйте позже", model.state.value.error)
        api.fail = null
        model.retry(); runCurrent()
        assertNull(model.state.value.error)
    }

    @Test
    fun withoutKeyNothingIsPicked() = runTest {
        val api = FakeApi()
        val model = GifSearchModel(api, backgroundScope, { dir }, canSend = false)
        assertNull(model.pick(media("aaaaaaaaaaaa")))
        assertEquals(GifSearchModel.NO_KEY, model.state.value.error)
        advanceTimeBy(5000); runCurrent()
        assertTrue(api.events.none { it.kind == GifkaEvent.Kind.CLICK })
    }

    @Test
    fun pickGivesPreviewAndDownloadsGifLater() = runTest {
        val api = FakeApi()
        val model = GifSearchModel(api, backgroundScope, { dir }, canSend = true)
        val pick = model.pick(media("abcabcabcabc"))!!
        assertTrue(pick.preview.isGif)
        assertEquals("https://x/abcabcabcabc.webp", pick.preview.url)
        val file = pick.prepare()
        assertEquals(OutgoingFile.Kind.PHOTO, file.kind)
        assertTrue(file.name.endsWith(".gif"))
        assertEquals(10, file.width)
        pick.onSent()
        advanceTimeBy(5000); runCurrent()
        assertEquals(listOf(GifkaEvent.Kind.CLICK, GifkaEvent.Kind.SEND), api.events.filter { it.mediaId == "abcabcabcabc" }.map { it.kind })
    }

    @Test
    fun viewsAreReportedOncePerItem() = runTest {
        val api = FakeApi()
        val model = GifSearchModel(api, backgroundScope, { dir }, canSend = true)
        model.open(); runCurrent()
        model.onQuery("x"); advanceTimeBy(500); runCurrent()
        model.onQuery(""); runCurrent()
        advanceTimeBy(5000); runCurrent()
        assertEquals(listOf("t", "x"), api.events.filter { it.kind == GifkaEvent.Kind.VIEW }.map { it.mediaId })
    }

    @Test
    fun reportRemovesItemAndShowsNotice() = runTest {
        val api = FakeApi()
        val model = GifSearchModel(api, backgroundScope, { dir }, canSend = true)
        model.open(); runCurrent()
        val item = model.state.value.items.single()
        model.report(item, GifkaReportReason.SPAM); runCurrent()
        assertTrue(model.state.value.items.isEmpty())
        assertEquals(listOf("t" to GifkaReportReason.SPAM), api.reports)
        assertEquals("Жалоба отправлена", model.state.value.notice)
    }
}
