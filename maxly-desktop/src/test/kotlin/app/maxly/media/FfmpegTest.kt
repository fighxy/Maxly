package app.maxly.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
