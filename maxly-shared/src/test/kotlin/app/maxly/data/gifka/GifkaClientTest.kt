package app.maxly.data.gifka

import app.maxly.domain.GifkaMedia
import app.maxly.domain.GifkaType
import kotlinx.coroutines.test.runTest
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.nio.file.Files

class GifkaClientTest {
    private val requests = mutableListOf<Request>()
    private var reply: (Request) -> Pair<Int, ByteArray> = { 200 to """{"items":[]}""".toByteArray() }
    private var headers: Map<String, String> = emptyMap()

    private fun http() = OkHttpClient.Builder().addInterceptor(Interceptor { chain ->
        val request = chain.request()
        requests += request
        val (code, body) = reply(request)
        Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(code).message("x")
            .apply { headers.forEach { (k, v) -> header(k, v) } }
            .body(body.toResponseBody("application/json".toMediaType())).build()
    }).build()

    private var clock = 0L
    private fun client(key: String = "") = GifkaClient(key, http(), baseUrl = "https://api.test", cacheTtlMs = 1000, now = { clock })
    private val media = GifkaMedia("m1", GifkaType.GIF, "", 100, 80, null, "https://x/w.webp", null, "https://api.test/v1/media/m1/download/gif")

    @Test
    fun searchSendsQueryTypeAndNoKey() = runTest {
        client().search("кот", GifkaType.GIF)
        val url = requests.single().url
        assertEquals("/v1/search", url.encodedPath)
        assertEquals("кот", url.queryParameter("q"))
        assertEquals("gif", url.queryParameter("type"))
        assertNull(requests.single().header("X-Api-Key"))
        assertNull(url.queryParameter("api_key"))
    }

    @Test
    fun keyGoesOnlyToHeader() = runTest {
        client("gk_test").trending()
        assertEquals("gk_test", requests.single().header("X-Api-Key"))
        assertEquals("/v1/media/trending", requests.single().url.encodedPath)
        assertTrue("gk_test" !in requests.single().url.toString())
    }

    @Test
    fun cachesWithinTtl() = runTest {
        val c = client()
        c.search("a"); c.search("a")
        assertEquals(1, requests.size)
        clock = 2000
        c.search("a")
        assertEquals(2, requests.size)
    }

    @Test
    fun rateLimitAndServerErrors() = runTest {
        reply = { 429 to "{}".toByteArray() }
        headers = mapOf("Retry-After" to "30")
        try { client().search("a"); fail() } catch (e: GifkaError.RateLimited) { assertEquals(30L, e.retryAfterSeconds) }
        reply = { 500 to "{}".toByteArray() }
        headers = emptyMap()
        try { client().search("b"); fail() } catch (e: GifkaError.Server) { assertEquals(500, e.code) }
    }

    @Test
    fun downloadNeedsKey() = runTest {
        val dir = Files.createTempDirectory("gifka").toFile()
        try { client().downloadGif(media, File(dir, "a.gif")); fail() } catch (_: GifkaError.KeyRequired) {}
        assertTrue(requests.isEmpty())
    }

    @Test
    fun downloadKeepsGifBytes() = runTest {
        val bytes = "GIF89a".toByteArray() + ByteArray(10) { it.toByte() }
        reply = { 200 to bytes }
        val dir = Files.createTempDirectory("gifka").toFile()
        val file = client("gk").downloadGif(media, File(dir, "m1.gif"))
        assertTrue(file.readBytes().contentEquals(bytes))
        assertEquals("gk", requests.single().header("X-Api-Key"))
        assertEquals("/v1/media/m1/download/gif", requests.single().url.encodedPath)
    }

    @Test
    fun downloadRejectsNonGif() = runTest {
        reply = { 200 to "<html>".toByteArray() }
        val dir = Files.createTempDirectory("gifka").toFile()
        val target = File(dir, "m1.gif")
        try { client("gk").downloadGif(media, target); fail() } catch (_: GifkaError.Server) {}
        assertTrue(!target.exists())
    }
}
