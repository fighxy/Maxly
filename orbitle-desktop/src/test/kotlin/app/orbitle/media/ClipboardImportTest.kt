package app.orbitle.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.awt.datatransfer.Clipboard
import java.awt.datatransfer.DataFlavor
import java.awt.datatransfer.Transferable
import java.awt.image.BufferedImage
import javax.imageio.ImageIO

/** Ctrl+V в поле сообщения: файлы и картинка — вложениями, текст — полю. */
class ClipboardImportTest {
    @get:Rule
    val temp = TemporaryFolder()

    private fun clipboard(vararg data: Pair<DataFlavor, Any>): Clipboard = Clipboard("test").apply {
        val map = data.toMap()
        setContents(object : Transferable {
            override fun getTransferDataFlavors() = map.keys.toTypedArray()
            override fun isDataFlavorSupported(flavor: DataFlavor) = flavor in map
            override fun getTransferData(flavor: DataFlavor) = map.getValue(flavor)
        }, null)
    }

    @Test
    fun copiedFilesAreAttached() {
        val photo = temp.newFile("photo.jpg")
        val folder = temp.newFolder("folder")
        assertEquals(listOf(photo), ClipboardImport.files(clipboard(DataFlavor.javaFileListFlavor to listOf(photo, folder))))
    }

    @Test
    fun screenshotBecomesPng() {
        val image = BufferedImage(40, 30, BufferedImage.TYPE_INT_RGB)
        val files = ClipboardImport.files(clipboard(DataFlavor.imageFlavor to image))
        assertEquals(1, files.size)
        assertEquals("image.png", files[0].name)
        val read = ImageIO.read(files[0])
        assertEquals(40, read.width)
        assertEquals(30, read.height)
        files[0].parentFile.deleteRecursively()
    }

    @Test
    fun textWinsOverPictureAndPlainTextIsLeftToField() {
        val image = BufferedImage(10, 10, BufferedImage.TYPE_INT_RGB)
        assertTrue(ClipboardImport.files(clipboard(DataFlavor.stringFlavor to "таблица", DataFlavor.imageFlavor to image)).isEmpty())
        assertTrue(ClipboardImport.files(clipboard(DataFlavor.stringFlavor to "привет")).isEmpty())
        assertTrue(ClipboardImport.files(clipboard()).isEmpty())
    }
}
