package app.maxly.media

import app.maxly.platform.AppPaths
import app.maxly.presentation.chat.SavedKind
import app.maxly.presentation.chat.ShareFile
import java.awt.Image
import java.awt.Toolkit
import java.awt.datatransfer.DataFlavor
import java.awt.datatransfer.Transferable
import java.awt.datatransfer.UnsupportedFlavorException
import java.io.File
import javax.imageio.ImageIO

/**
 * «Поделиться» на компьютере — копия в буфер обмена: файл (вставляется в проводник, Finder и
 * мессенджеры), а у фото ещё и картинка (вставляется в редакторы и письма).
 */
object DesktopShare {
    fun copy(file: ShareFile): Boolean = runCatching {
        val folder = File(AppPaths.cacheDir, "share").apply { mkdirs() }
        folder.listFiles()?.forEach { it.delete() }
        val copy = File(file.path).copyTo(File(folder, file.name), overwrite = true)
        // WebP и HEIC Java не читает: тогда в буфере только файл.
        val image = if (file.kind == SavedKind.IMAGE) runCatching { ImageIO.read(copy) }.getOrNull() else null
        Toolkit.getDefaultToolkit().systemClipboard.setContents(FileTransfer(copy, image), null)
        true
    }.getOrDefault(false)

    private class FileTransfer(private val file: File, private val image: Image?) : Transferable {
        private val flavors = listOfNotNull(DataFlavor.javaFileListFlavor, image?.let { DataFlavor.imageFlavor })

        override fun getTransferDataFlavors(): Array<DataFlavor> = flavors.toTypedArray()

        override fun isDataFlavorSupported(flavor: DataFlavor): Boolean = flavor in flavors

        override fun getTransferData(flavor: DataFlavor): Any = when {
            flavor == DataFlavor.javaFileListFlavor -> listOf(file)
            flavor == DataFlavor.imageFlavor && image != null -> image
            else -> throw UnsupportedFlavorException(flavor)
        }
    }
}
