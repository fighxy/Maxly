package app.maxly.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class FfmpegTest {
    private val dir: File = Files.createTempDirectory("maxly-ffmpeg").toFile().apply { deleteOnExit() }

    private fun touch(name: String) = File(dir, name).apply { writeText("x"); deleteOnExit() }

    @Test
    fun bundledBinaryWinsOverPath() {
        touch("ffmpeg")
        val tried = mutableListOf<String>()
        val found = Ffmpeg.resolve(null, dir.absolutePath, HostOs.LINUX, prepare = { it }, works = { tried += it; true })
        assertEquals(Ffmpeg.Origin.BUNDLED, found?.origin)
        assertEquals(File(dir, "ffmpeg").absolutePath, found?.path)
        assertEquals(1, tried.size)
    }

    @Test
    fun windowsLooksForExe() {
        touch("ffmpeg.exe")
        val found = Ffmpeg.resolve(null, dir.absolutePath, HostOs.WINDOWS, prepare = { it }, works = { true })
        assertEquals(File(dir, "ffmpeg.exe").absolutePath, found?.path)
        assertEquals("ffmpeg", Ffmpeg.fileName(HostOs.MACOS))
    }

    @Test
    fun explicitPathComesFirst() {
        val own = touch("my-ffmpeg")
        touch("ffmpeg")
        val found = Ffmpeg.resolve(own.absolutePath, dir.absolutePath, HostOs.LINUX, prepare = { it }, works = { true })
        assertEquals(Ffmpeg.Origin.OVERRIDE, found?.origin)
        assertEquals(own.absolutePath, found?.path)
    }

    /** Свой не запускается (битый, без бита исполнения) — берётся ffmpeg из PATH. */
    @Test
    fun brokenBundleFallsBackToPath() {
        touch("ffmpeg")
        val found = Ffmpeg.resolve(null, dir.absolutePath, HostOs.LINUX, prepare = { it }, works = { it == "ffmpeg" })
        assertEquals(Ffmpeg.Binary("ffmpeg", Ffmpeg.Origin.PATH), found)
        val unprepared = Ffmpeg.resolve(null, dir.absolutePath, HostOs.LINUX, prepare = { null }, works = { true })
        assertEquals(Ffmpeg.Origin.PATH, unprepared?.origin)
    }

    @Test
    fun noFfmpegAnywhere() {
        assertNull(Ffmpeg.resolve(null, null, HostOs.LINUX, prepare = { it }, works = { false }))
        assertNull(Ffmpeg.resolve(null, dir.absolutePath, HostOs.LINUX, prepare = { it }, works = { false }))
    }

    @Test
    fun systemEncodersComeFirstPerOs() {
        assertEquals("h264_mf", H264Encoders.candidates(HostOs.WINDOWS, emptyList()).first().name)
        assertEquals("h264_videotoolbox", H264Encoders.candidates(HostOs.MACOS, emptyList()).first().name)
        val linux = H264Encoders.candidates(HostOs.LINUX, listOf("/dev/dri/renderD128", "/dev/dri/renderD129"))
        assertEquals(listOf("h264_vaapi", "h264_vaapi", "libopenh264", "libx264"), linux.map { it.name })
        assertEquals(listOf("-vaapi_device", "/dev/dri/renderD129"), linux[1].global)
        // Без видеокарты на Linux системного кодировщика нет.
        assertEquals(listOf("libopenh264", "libx264"), H264Encoders.candidates(HostOs.LINUX, emptyList()).map { it.name })
    }

    @Test
    fun encodeCommandPutsDeviceBeforeInputAndCodecAfter() {
        val vaapi = H264Encoders.candidates(HostOs.LINUX, listOf("/dev/dri/renderD128")).first()
        val command = H264Encoders.encodeCommand("/opt/ffmpeg", vaapi, 480, 25, "/tmp/out.mp4")
        assertEquals("/opt/ffmpeg", command.first())
        assertEquals("/tmp/out.mp4", command.last())
        assertTrue(command.indexOf("-vaapi_device") < command.indexOf("-i"))
        assertTrue(command.indexOf("h264_vaapi") > command.indexOf("-i"))
        assertTrue(command.containsAll(listOf("480x480", "pipe:0", "format=nv12,hwupload")))
        assertFalse("libx264" in command)
    }

    @Test
    fun pickTakesFirstWorking() {
        val candidates = H264Encoders.candidates(HostOs.WINDOWS, emptyList())
        assertEquals("libopenh264", H264Encoders.pick(candidates) { it.name != "h264_mf" }?.name)
        assertNull(H264Encoders.pick(candidates) { false })
    }

    @Test
    fun unavailableTextNamesTheFix() {
        assertTrue("Media Feature Pack" in H264Encoders.unavailableText(HostOs.WINDOWS, ffmpegFound = true))
        assertTrue("VA-API" in H264Encoders.unavailableText(HostOs.LINUX, ffmpegFound = true))
        assertTrue("VideoToolbox" in H264Encoders.unavailableText(HostOs.MACOS, ffmpegFound = true))
        assertTrue("не найден ffmpeg" in H264Encoders.unavailableText(HostOs.WINDOWS, ffmpegFound = false))
    }
}
