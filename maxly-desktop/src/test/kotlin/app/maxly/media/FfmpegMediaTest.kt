package app.maxly.media

import org.junit.Assert.assertEquals
import kotlin.test.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit

/**
 * То, что ffmpeg делает в приложении: GIF (MP4 H.264) в кадры RGBA, голосовое в Ogg/Opus и
 * обратно в PCM. Идут с ffmpeg из сборки (`maxly.ffmpeg`) или из PATH.
 */
class FfmpegMediaTest {
    private val gif = File("src/test/resources/media/gif-h264.mp4")

    private fun run(command: List<String>, input: ByteArray? = null): Pair<Int, ByteArray> {
        val process = ProcessBuilder(command).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        val writer = Thread { runCatching { process.outputStream.use { out -> input?.let(out::write) } } }.apply { start() }
        val output = process.inputStream.readBytes()
        writer.join()
        assertTrue(process.waitFor(60, TimeUnit.SECONDS))
        return process.exitValue() to output
    }

    /** Собранный свой ffmpeg (Gradle передаёт его в `maxly.ffmpeg`) берётся вместо PATH. */
    @Test
    fun builtFfmpegIsPicked() {
        val given = System.getProperty("maxly.ffmpeg")
        assumeTrue("свой ffmpeg не собран", given != null)
        assertEquals(Ffmpeg.Binary(File(given!!).absolutePath, Ffmpeg.Origin.OVERRIDE), Ffmpeg.binary)
        val (code, version) = run(Ffmpeg.command("-hide_banner", "-version"))
        assertEquals(0, code)
        val text = version.toString(Charsets.UTF_8)
        assertTrue(text, "--disable-autodetect" in text && "--enable-gpl" !in text && "libx264" !in text && "openh264" !in text)
    }

    @Test
    fun gifMp4DecodesToRgbaFrames() {
        assumeTrue("нет ffmpeg", Ffmpeg.binary != null)
        val (code, output) = run(VideoCommands.video(gif.absolutePath, 0))
        assertEquals(0, code)
        val reader = PamReader(output.inputStream())
        val first = assertNotNull(reader.next())
        assertEquals(96, first.width)
        assertEquals(64, first.height)
        var frames = 1
        while (reader.next() != null) frames++
        // Секунда ролика при 30 кадрах в секунду на выходе.
        assertTrue("кадров $frames", frames in 28..32)
    }

    @Test
    fun voiceIsEncodedToOpusAndPlaysBack() {
        assumeTrue("нет ffmpeg", Ffmpeg.binary != null)
        val wav = Files.createTempFile("maxly-voice", ".wav").toFile().apply { deleteOnExit() }
        val ogg = File(wav.parentFile, wav.nameWithoutExtension + ".ogg").apply { deleteOnExit() }
        assertEquals(0, run(Ffmpeg.command("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1:sample_rate=48000", wav.absolutePath)).first)
        // Те же ключи, что у DesktopVoiceRecorder.finish.
        val encode = Ffmpeg.command("-y", "-hide_banner", "-loglevel", "error", "-i", wav.absolutePath, "-c:a", "libopus", "-b:a", "32k", "-ac", "1", "-ar", "48000", ogg.absolutePath)
        assertEquals(0, run(encode).first)
        assertTrue(ogg.length() > 0)
        assertEquals("OggS", ogg.readBytes().copyOfRange(0, 4).toString(Charsets.US_ASCII))
        // Как у DesktopVoicePlayer: PCM 48 кГц моно.
        val (code, pcm) = run(Ffmpeg.command("-hide_banner", "-loglevel", "error", "-i", ogg.absolutePath, "-af", "atempo=1.0", "-f", "s16le", "-ac", "1", "-ar", "48000", "-"))
        assertEquals(0, code)
        val seconds = pcm.size / 2 / 48_000.0
        assertTrue("PCM $seconds с", seconds in 0.9..1.1)
    }
}
