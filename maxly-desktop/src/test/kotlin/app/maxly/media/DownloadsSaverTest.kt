package app.maxly.media

import app.maxly.presentation.chat.SavedKind
import kotlinx.coroutines.runBlocking
import org.jetbrains.skia.Color
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Surface
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class DownloadsSaverTest {
    private val dir = Files.createTempDirectory("saved").toFile().apply { deleteOnExit() }

    private fun webp(): java.io.File {
        val surface = Surface.makeRasterN32Premul(8, 6)
        surface.canvas.clear(Color.RED)
        val bytes = surface.makeImageSnapshot().encodeToData(EncodedImageFormat.WEBP, 90)!!.bytes
        return Files.createTempFile("photo", ".webp").toFile().apply { writeBytes(bytes) }
    }

    @Test
    fun webpPhotoIsSavedAsJpegInTheChosenFolder() = runBlocking {
        DownloadsSaver().save(webp().path, "Maxly 1.webp", SavedKind.IMAGE, dir.path)
        DownloadsSaver().save(webp().path, "Maxly 1.webp", SavedKind.IMAGE, dir.path)
        assertEquals(listOf("Maxly 1 2.jpg", "Maxly 1.jpg"), dir.list()!!.sorted())
        val bytes = dir.resolve("Maxly 1.jpg").readBytes()
        assertArrayEquals(byteArrayOf(0xFF.toByte(), 0xD8.toByte()), bytes.copyOf(2))
        val image = org.jetbrains.skia.Image.makeFromEncoded(bytes)
        assertEquals(8 to 6, image.width to image.height)
    }

    @Test
    fun filesAndUnreadableImagesAreCopiedAsIs() = runBlocking {
        val file = Files.createTempFile("doc", ".pdf").toFile().apply { writeText("pdf") }
        DownloadsSaver().save(file.path, "отчёт.pdf", SavedKind.OTHER, dir.path)
        val broken = Files.createTempFile("bad", ".webp").toFile().apply { writeText("not an image") }
        DownloadsSaver().save(broken.path, "bad.webp", SavedKind.IMAGE, dir.path)
        assertEquals("pdf", dir.resolve("отчёт.pdf").readText())
        assertTrue(dir.resolve("bad.webp").isFile)
    }
}
