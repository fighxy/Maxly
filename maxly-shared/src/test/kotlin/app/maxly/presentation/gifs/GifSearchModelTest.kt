package app.maxly.presentation.gifs

import app.maxly.data.gifka.GifkaApi
import app.maxly.data.gifka.GifkaError
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
    fun withoutKeyNothingIsDownloaded() = runTest {
        val model = GifSearchModel(FakeApi(), backgroundScope, { dir }, canSend = false)
        assertNull(model.prepare(media("a")))
        assertEquals(GifSearchModel.NO_KEY, model.state.value.error)
    }

    @Test
    fun preparedFileIsGifPhoto() = runTest {
        val model = GifSearchModel(FakeApi(), backgroundScope, { dir }, canSend = true)
        val file = model.prepare(media("abc"))!!
        assertEquals(OutgoingFile.Kind.PHOTO, file.kind)
        assertTrue(file.name.endsWith(".gif"))
        assertEquals(10, file.width)
        assertNull(model.state.value.sendingId)
    }
}
