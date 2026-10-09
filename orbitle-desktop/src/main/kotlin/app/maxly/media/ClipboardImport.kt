package app.maxly.media

import app.maxly.data.diagnostics.AppLog
import app.maxly.platform.AppPaths
import java.awt.Image
import java.awt.Toolkit
import java.awt.datatransfer.Clipboard
import java.awt.datatransfer.DataFlavor
import java.awt.image.BufferedImage
import java.awt.image.MultiResolutionImage
import java.io.File
import java.util.UUID
import javax.imageio.ImageIO

/**
 * Что вставить из буфера обмена вложениями: скопированные в проводнике файлы или картинку
 * (скриншот, «Копировать изображение» в браузере). Текст — не наше: его вставляет само поле.
 */
object ClipboardImport {
    /**
     * Файлы для вложений или пустой список, если в буфере их нет. Картинка сохраняется в PNG
     * в кэше. Когда в буфере есть и текст, и картинка (так кладут Word и Excel), побеждает текст.
     */
    fun files(clipboard: Clipboard = Toolkit.getDefaultToolkit().systemClipboard): List<File> = try {
        when {
            clipboard.isDataFlavorAvailable(DataFlavor.javaFileListFlavor) ->
                (clipboard.getData(DataFlavor.javaFileListFlavor) as? List<*>).orEmpty().filterIsInstance<File>().filter { it.isFile }
            clipboard.isDataFlavorAvailable(DataFlavor.stringFlavor) -> emptyList()
            clipboard.isDataFlavorAvailable(DataFlavor.imageFlavor) ->
                listOfNotNull((clipboard.getData(DataFlavor.imageFlavor) as? Image)?.let(::savePng))
            else -> emptyList()
        }
    } catch (e: Exception) {
        // Буфер занят другой программой или формат не читается: обычная вставка текста.
        AppLog.w("clipboard", "Не прочитал буфер обмена", e)
        emptyList()
    }

    /** Картинка из буфера — PNG-файл `image.png` в кэше исходящих. */
    fun savePng(image: Image, dir: File = File(AppPaths.cacheDir, "outgoing/${UUID.randomUUID()}")): File? {
        val buffered = toBuffered(image) ?: return null
        dir.mkdirs()
        val file = File(dir, "image.png")
        return if (ImageIO.write(buffered, "png", file)) file else null
    }

    private fun toBuffered(image: Image): BufferedImage? {
        // На экране с масштабом Windows отдаёт набор размеров: берётся самый большой.
        val source = (image as? MultiResolutionImage)?.resolutionVariants?.maxByOrNull { it.getWidth(null) * it.getHeight(null) } ?: image
        if (source is BufferedImage) return source
        val width = source.getWidth(null)
        val height = source.getHeight(null)
        if (width <= 0 || height <= 0) return null
        val copy = BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB)
        val graphics = copy.createGraphics()
        try {
            graphics.drawImage(source, 0, 0, null)
        } finally {
            graphics.dispose()
        }
        return copy
    }
}
