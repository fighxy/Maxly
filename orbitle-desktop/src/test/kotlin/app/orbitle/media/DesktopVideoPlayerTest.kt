package app.orbitle.media

import androidx.compose.ui.graphics.toPixelMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

class DesktopVideoPlayerTest {
    private fun pam(width: Int, height: Int, fill: Byte): ByteArray =
        "P7\nWIDTH $width\nHEIGHT $height\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n".toByteArray() +
            ByteArray(width * height * 4) { fill }

    @Test
    fun pamFramesCarryTheirOwnSize() {
        val stream = pam(2, 1, 7) + pam(1, 3, 9) + pam(4, 4, 1).copyOf(30)
        val reader = PamReader(BufferedInputStream(ByteArrayInputStream(stream)))
        val first = reader.next()!!
        assertEquals(2, first.width)
        assertEquals(1, first.height)
        assertEquals(8, first.rgba.size)
        assertTrue(first.rgba.all { it == 7.toByte() })
        val second = reader.next()!!
        assertEquals(1 to 3, second.width to second.height)
        // Обрыв посреди кадра — конец потока, а не ошибка.
        assertNull(reader.next())
        assertNull(reader.next())
    }

    @Test
    fun clockStandsUntilStartedAndKeepsPauses() {
        var now = 0L
        val clock = PlaybackClock(5_000) { now }
        now = 2_000_000_000
        assertEquals(5_000, clock.nowMs())
        clock.resume()
        now += 1_500_000_000
        assertEquals(6_500, clock.nowMs())
        clock.pause()
        now += 10_000_000_000
        assertEquals(6_500, clock.nowMs())
        assertFalse(clock.isRunning)
        clock.resume()
        now += 500_000_000
        assertEquals(7_000, clock.nowMs())
    }

    @Test
    fun commandsAndDuration() {
        assertEquals("12.345", VideoCommands.seconds(12_345))
        assertEquals("0.000", VideoCommands.seconds(-5))
        val video = VideoCommands.video("/tmp/a.mp4", 1_500)
        assertEquals("1.500", video[video.indexOf("-ss") + 1])
        assertTrue(video.containsAll(listOf("-an", "image2pipe", "pam", "rgba")))
        assertTrue(VideoCommands.audio("/tmp/a.mp4", 0).containsAll(listOf("-vn", "s16le")))
        assertEquals(62_500L, VideoCommands.durationMs("  Duration: 00:01:02.50, start: 0.000000, bitrate: 900 kb/s"))
        assertEquals(3_723_000L, VideoCommands.durationMs("Duration: 01:02:03.00,"))
        assertNull(VideoCommands.durationMs("  Duration: N/A, bitrate: N/A"))
    }

    private fun ffmpeg(): Boolean = runCatching {
        ProcessBuilder("ffmpeg", "-version").redirectErrorStream(true).start().apply { inputStream.readBytes() }.waitFor() == 0
    }.getOrDefault(false)

    /** Ролик из генератора ffmpeg: полосы и тон. */
    private fun sample(width: Int, height: Int, seconds: Double, audio: Boolean = true): File {
        val file = Files.createTempFile("orbitle-video", ".mp4").toFile().apply { deleteOnExit() }
        val args = mutableListOf("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=${width}x$height:rate=25:duration=$seconds")
        if (audio) args += listOf("-f", "lavfi", "-i", "sine=frequency=440:duration=$seconds")
        args += listOf("-pix_fmt", "yuv420p", "-shortest", file.absolutePath)
        val code = ProcessBuilder(args).redirectErrorStream(true).start().apply { inputStream.readBytes() }.waitFor()
        assertEquals(0, code)
        return file
    }

    @Test
    fun ffmpegDecodesAtConstantRateAndScalesDown() {
        assumeTrue("нет ffmpeg в PATH", ffmpeg())
        val file = sample(1920, 1080, 1.0, audio = false)
        val process = ProcessBuilder(VideoCommands.video(file.absolutePath, 0)).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        val reader = PamReader(BufferedInputStream(process.inputStream, 1 shl 20))
        var frames = 0
        var size = 0 to 0
        while (true) {
            val frame = reader.next() ?: break
            size = frame.width to frame.height
            frames++
        }
        process.waitFor()
        // 25 кадров исходника становятся 30: время кадра — его номер.
        assertTrue("кадров $frames", frames in 29..31)
        assertEquals(960 to 540, size)
    }

    @Test
    fun playerShowsFramesLearnsDurationAndEnds(): Unit = runBlocking {
        assumeTrue("нет ffmpeg в PATH", ffmpeg())
        val file = sample(320, 240, 1.0)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open(file.absolutePath, "test")
            val playing = withTimeout(10_000) { player.state.first { it.frame != null } }
            assertNotNull(playing.frame)
            assertEquals(320, playing.frame!!.width)
            assertFalse(playing.failed)
            val ended = withTimeout(10_000) { player.state.first { it.ended } }
            assertEquals(1_000L, ended.durationMs)
            assertFalse(ended.isPlaying)
            // Перемотка в начало после конца снова показывает кадры.
            player.play()
            withTimeout(10_000) { player.state.first { !it.ended && it.isPlaying && it.positionMs < 500 && !it.isBuffering } }
        } finally {
            player.release()
            scope.cancel()
        }
    }

    @Test
    fun colorsArriveAsRgba(): Unit = runBlocking {
        assumeTrue("нет ffmpeg в PATH", ffmpeg())
        val file = Files.createTempFile("orbitle-red", ".mp4").toFile().apply { deleteOnExit() }
        val code = ProcessBuilder(
            "ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=red:size=64x64:rate=25:duration=0.5",
            "-pix_fmt", "yuv420p", file.absolutePath,
        ).redirectErrorStream(true).start().apply { inputStream.readBytes() }.waitFor()
        assertEquals(0, code)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open(file.absolutePath, "test", muted = true)
            val frame = withTimeout(10_000) { player.state.first { it.frame != null } }.frame!!
            val pixel = frame.toPixelMap()[32, 32]
            assertTrue("цвет $pixel", pixel.red > 0.8f && pixel.green < 0.2f && pixel.blue < 0.2f && pixel.alpha > 0.99f)
        } finally {
            player.release()
            scope.cancel()
        }
    }

    @Test
    fun missingFileFails(): Unit = runBlocking {
        assumeTrue("нет ffmpeg в PATH", ffmpeg())
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val player = DesktopVideoPlayer(scope)
        try {
            player.open("/nonexistent/orbitle.mp4", "test")
            val failed = withTimeout(10_000) { player.state.first { it.failed } }
            assertFalse(failed.isPlaying)
        } finally {
            player.release()
            scope.cancel()
        }
    }
}
