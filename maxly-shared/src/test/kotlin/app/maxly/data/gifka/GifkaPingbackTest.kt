package app.maxly.data.gifka

import app.maxly.domain.GifkaMedia
import app.maxly.domain.GifkaPage
import app.maxly.domain.GifkaType
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class GifkaPingbackTest {
    private class Recorder(val fail: Boolean = false) : GifkaApi {
        val batches = mutableListOf<List<GifkaEvent>>()
        override suspend fun search(query: String, type: GifkaType, limit: Int, offset: Int) = GifkaPage(emptyList(), 0)
        override suspend fun trending(type: GifkaType, limit: Int, offset: Int) = GifkaPage(emptyList(), 0)
        override suspend fun downloadGif(media: GifkaMedia, target: File) = target
        override suspend fun pingback(events: List<GifkaEvent>) { batches += events; if (fail) error("offline") }
        override suspend fun report(mediaId: String, reason: GifkaReportReason, details: String?) = Unit
    }

    @Test
    fun batchesAfterDelayAndDedupesViews() = runTest {
        val api = Recorder()
        val pingback = GifkaPingback(api, backgroundScope, delayMs = 1000)
        pingback.views(listOf("a", "b"))
        pingback.views(listOf("b", "c"))
        pingback.click("a")
        advanceTimeBy(500); runCurrent()
        assertTrue(api.batches.isEmpty())
        advanceTimeBy(600); runCurrent()
        assertEquals(1, api.batches.size)
        assertEquals(listOf("a" to "view", "b" to "view", "c" to "view", "a" to "click"), api.batches.single().map { it.mediaId to it.kind.raw })
    }

    @Test
    fun fullBatchGoesAtOnceAndErrorsAreSwallowed() = runTest {
        val api = Recorder(fail = true)
        val pingback = GifkaPingback(api, backgroundScope, delayMs = 60_000, maxBatch = 3)
        pingback.views(listOf("a", "b", "c", "d"))
        runCurrent()
        assertEquals(listOf(3, 1), api.batches.map { it.size })
        pingback.send("a")
        advanceTimeBy(61_000); runCurrent()
        assertEquals(3, api.batches.size)
    }
}
