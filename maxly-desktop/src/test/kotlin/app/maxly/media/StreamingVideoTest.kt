package app.maxly.media

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.nio.file.Files
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

class StreamingVideoTest {
    /** Медленный источник: [chunk] байт за [pauseMs], с диапазонами или без. */
    private class Slow(val data: ByteArray, val chunk: Int = 64 * 1024, val pauseMs: Long = 0, val ranges: Boolean = true) : VideoUpstream {
        val opened = CopyOnWriteArrayList<Long>()

        override fun open(from: Long): UpstreamBody {
            opened += from
            val start = if (ranges) from else 0L
            val input = object : InputStream() {
                var pos = start.toInt()
                override fun read(): Int = if (pos >= data.size) -1 else data[pos++].toInt() and 0xff
                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    if (pos >= data.size) return -1
                    if (pauseMs > 0) Thread.sleep(pauseMs)
                    val n = minOf(len, chunk, data.size - pos)
                    System.arraycopy(data, pos, b, off, n)
                    pos += n
                    return n
                }
            }
            return UpstreamBody(input, start, data.size.toLong()) {}
        }
    }

    private fun bytes(size: Int) = ByteArray(size) { (it * 31 + it / 7).toByte() }

    private fun target(): File = Files.createTempDirectory("stream").toFile().resolve("video.mp4").apply { parentFile.deleteOnExit() }

    private fun get(url: String, range: String? = null): Triple<Int, Map<String, String>, ByteArray> {
        val connection = URI(url).toURL().openConnection(java.net.Proxy.NO_PROXY) as HttpURLConnection
        range?.let { connection.setRequestProperty("Range", it) }
        val code = connection.responseCode
        val headers = connection.headerFields.filterKeys { it != null }.mapValues { it.value.first() }
        val body = (if (code < 400) connection.inputStream else connection.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
        return Triple(code, headers, body)
    }

    @Test
    fun rangeHeader() {
        assertEquals(0L..99L, ByteRange.parse(null, 100))
        assertEquals(10L..99L, ByteRange.parse("bytes=10-", 100))
        assertEquals(10L..20L, ByteRange.parse("bytes=10-20", 100))
        assertEquals(10L..99L, ByteRange.parse("bytes=10-500", 100))
        assertEquals(90L..99L, ByteRange.parse("bytes=-10", 100))
        assertNull(ByteRange.parse("bytes=100-", 100))
        assertEquals(0L..99L, ByteRange.parse("items=1", 100))
    }

    @Test
    fun servesWhileDownloadingAndKeepsTheFile() {
        val data = bytes(600_000)
        val source = Slow(data, chunk = 20_000, pauseMs = 5)
        val download = StreamingDownload(source, target())
        thread { download.run() }
        val url = LocalVideoServer.register(download)
        try {
            val (code, headers, body) = get(url)
            assertEquals(200, code)
            assertEquals("bytes", headers["Accept-Ranges"])
            assertArrayEquals(data, body)
            val (partial, rangeHeaders, slice) = get(url, "bytes=1000-1999")
            assertEquals(206, partial)
            assertEquals("bytes 1000-1999/600000", rangeHeaders["Content-Range"])
            assertArrayEquals(data.copyOfRange(1000, 2000), slice)
            assertEquals(416, get(url, "bytes=600000-").first)
            runBlocking { withTimeout(10_000) { assertTrue(download.awaitFinished()) } }
            assertArrayEquals(data, download.target.readBytes())
            assertFalse(File(download.target.parentFile, "video.mp4.stream").exists())
            // Одна загрузка на всё: диапазоны внутри скачанного к источнику не ходят.
            assertEquals(listOf(0L), source.opened.toList())
        } finally {
            LocalVideoServer.unregister(url)
        }
    }

    @Test
    fun farRangeGoesStraightToTheSource() {
        val data = bytes(6 * 1024 * 1024)
        val source = Slow(data, chunk = 16 * 1024, pauseMs = 20)
        val download = StreamingDownload(source, target())
        thread { download.run() }
        val url = LocalVideoServer.register(download)
        try {
            val from = data.size - 100_000
            val (code, _, body) = get(url, "bytes=$from-")
            assertEquals(206, code)
            assertArrayEquals(data.copyOfRange(from, data.size), body)
            assertEquals(listOf(0L, from.toLong()), source.opened.toList())
            assertFalse(download.finished)
        } finally {
            download.cancel()
            LocalVideoServer.unregister(url)
        }
    }

    @Test
    fun withoutRangesTheFarPlaceWaitsForTheDownload() {
        val data = bytes(3 * 1024 * 1024)
        val source = Slow(data, chunk = 256 * 1024, ranges = false)
        val download = StreamingDownload(source, target())
        thread { download.run() }
        val url = LocalVideoServer.register(download)
        try {
            val from = data.size - 10
            val (code, _, body) = get(url, "bytes=$from-")
            assertEquals(206, code)
            assertArrayEquals(data.copyOfRange(from, data.size), body)
        } finally {
            LocalVideoServer.unregister(url)
        }
    }

    private fun ffmpeg(): Boolean = Ffmpeg.binary != null

    private fun sample(seconds: Double, faststart: Boolean, size: String = "320x240", bitrate: String? = null): ByteArray {
        val file = Files.createTempFile("maxly-stream", ".mp4").toFile().apply { deleteOnExit() }
        val args = mutableListOf(
            Ffmpeg.path, "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=$size:rate=25:duration=$seconds" + (if (bitrate != null) ",noise=alls=60:allf=t+u" else ""),
            "-f", "lavfi", "-i", "sine=frequency=440:duration=$seconds",
            "-pix_fmt", "yuv420p", "-shortest",
        )
        if (bitrate != null) args += listOf("-b:v", bitrate, "-maxrate", bitrate, "-bufsize", bitrate)
        if (faststart) args += listOf("-movflags", "+faststart")
        args += file.absolutePath
        assertEquals(0, ProcessBuilder(args).redirectErrorStream(true).start().apply { inputStream.readBytes() }.waitFor())
        return file.readBytes()
    }

    /**
     * Ролик с «CDN» (тот же локальный сервер поверх медленного источника): первый кадр — раньше,
     * чем ролик скачался; после загрузки он в кэше.
     */
    @Test
    fun playerStartsBeforeTheDownloadEnds(): Unit = runBlocking {
        assumeTrue("нет ffmpeg", ffmpeg())
        val data = sample(6.0, faststart = true)
        // Весь ролик идёт ~3 с.
        val cdn = StreamingDownload(Slow(data, chunk = maxOf(4096, data.size / 150), pauseMs = 20), target())
        thread { cdn.run() }
        val url = LocalVideoServer.register(cdn)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open(url, "test", muted = true)
            val first = withTimeout(15_000) { player.state.first { it.frame != null } }
            assertTrue("буфер ${first.buffered}", first.buffered < 1f)
            assertNull(first.downloading)
            assertFalse(first.failed)
            val cached = withTimeout(15_000) { player.state.first { it.buffered >= 1f } }
            assertFalse(cached.failed)
            assertArrayEquals(data, DesktopVideo.local(url, "test")!!.readBytes())
        } finally {
            player.release()
            scope.cancel()
            LocalVideoServer.unregister(url)
            DesktopVideo.local(url, "test")?.parentFile?.deleteRecursively()
        }
    }

    /** Индекс в конце файла: ffmpeg берёт его диапазоном у источника и начинает до конца загрузки. */
    @Test
    fun moovAtTheEndIsFetchedByRange(): Unit = runBlocking {
        assumeTrue("нет ffmpeg", ffmpeg())
        val data = sample(5.0, faststart = false, size = "1280x720", bitrate = "8M")
        assertTrue("ролик ${data.size} Б должен быть больше AHEAD", data.size > StreamingDownload.AHEAD * 3 / 2)
        // Около 1,6 МБ/с: весь ролик качается несколько секунд.
        val source = Slow(data, chunk = 64 * 1024, pauseMs = 40)
        val cdn = StreamingDownload(source, target())
        thread { cdn.run() }
        val url = LocalVideoServer.register(cdn)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open(url, "test", muted = true)
            val first = withTimeout(30_000) { player.state.first { it.frame != null || it.failed } }
            assertFalse(first.failed)
            assertTrue("буфер ${first.buffered}", first.buffered < 1f)
            assertTrue("к источнику: ${source.opened}", source.opened.any { it > 0 })
        } finally {
            player.release()
            scope.cancel()
            cdn.cancel()
            LocalVideoServer.unregister(url)
            DesktopVideo.local(url, "test")?.parentFile?.deleteRecursively()
        }
    }

    /** Перемотка вперёд за край загрузки: кадр с нужного места приходит, не дожидаясь загрузки. */
    @Test
    fun seekAheadWhileDownloading(): Unit = runBlocking {
        assumeTrue("нет ffmpeg", ffmpeg())
        val data = sample(6.0, faststart = true, size = "1280x720", bitrate = "8M")
        // Около 0,8 МБ/с: до конца ролика загрузка дойдёт нескоро.
        val cdn = StreamingDownload(Slow(data, chunk = 32 * 1024, pauseMs = 40), target())
        thread { cdn.run() }
        val url = LocalVideoServer.register(cdn)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open(url, "test", muted = true)
            withTimeout(20_000) { player.state.first { it.frame != null && it.durationMs > 0 } }
            player.seek(0.8f)
            val later = withTimeout(20_000) { player.state.first { it.positionMs >= 4_800 && !it.isBuffering && it.frame != null } }
            assertFalse(later.failed)
            assertTrue("буфер ${later.buffered}", later.buffered < 1f)
        } finally {
            player.release()
            scope.cancel()
            cdn.cancel()
            LocalVideoServer.unregister(url)
            DesktopVideo.local(url, "test")?.parentFile?.deleteRecursively()
        }
    }

    /** Сеть медленнее ролика: проигрыватель встаёт на буферизацию с кадром на экране и доигрывает до конца. */
    @Test
    fun slowNetworkBuffersAndPlaysOn(): Unit = runBlocking {
        assumeTrue("нет ffmpeg", ffmpeg())
        val data = sample(3.0, faststart = true, size = "1280x720", bitrate = "8M")
        // Примерно вдвое медленнее, чем ролик играет.
        val perSecond = data.size / 6
        val cdn = StreamingDownload(Slow(data, chunk = perSecond / 25, pauseMs = 40), target())
        thread { cdn.run() }
        val url = LocalVideoServer.register(cdn)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open(url, "test", muted = true)
            withTimeout(20_000) { player.state.first { it.frame != null } }
            val stalled = withTimeout(20_000) { player.state.first { it.isBuffering && it.frame != null && it.isPlaying } }
            val ended = withTimeout(30_000) { player.state.first { it.ended || it.failed } }
            assertFalse(ended.failed)
            assertTrue("стоял на ${stalled.positionMs}, закончил на ${ended.positionMs}", ended.positionMs > stalled.positionMs)
        } finally {
            player.release()
            scope.cancel()
            cdn.cancel()
            LocalVideoServer.unregister(url)
            DesktopVideo.local(url, "test")?.parentFile?.deleteRecursively()
        }
    }
}
