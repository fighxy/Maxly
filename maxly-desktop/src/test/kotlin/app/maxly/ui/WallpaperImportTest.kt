package app.maxly.ui

import app.maxly.ui.components.importWallpaper
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class WallpaperImportTest {
    private val fixture = File("src/test/resources/wallpaper/rotate90.jpg")

    @Test
    fun copyIsDownscaledAndRotatedByExif() {
        // 3000×1000, левая половина красная, правая синяя, EXIF «повернуть на 90° по часовой».
        val target = Files.createTempFile("wallpaper", ".jpg").toFile()
        assertTrue(importWallpaper(fixture, target))
        val image = Image.makeFromEncoded(target.readBytes())
        assertEquals(853, image.width)
        assertEquals(2560, image.height)
        val bitmap = Bitmap.makeFromImage(image)
        val top = bitmap.getColor(426, 200)
        val bottom = bitmap.getColor(426, 2360)
        // После поворота левая (красная) половина оказывается сверху.
        assertTrue(red(top) > 200 && blue(top) < 60)
        assertTrue(blue(bottom) > 200 && red(bottom) < 60)
        target.delete()
    }

    @Test
    fun unreadableFileLeavesNoCopy() {
        val source = Files.createTempFile("broken", ".heic").toFile().apply { writeText("не картинка") }
        val target = Files.createTempFile("wallpaper", ".jpg").toFile()
        assertFalse(importWallpaper(source, target))
        assertFalse(target.exists())
    }

    private fun red(color: Int) = (color shr 16) and 0xFF
    private fun blue(color: Int) = color and 0xFF
}
