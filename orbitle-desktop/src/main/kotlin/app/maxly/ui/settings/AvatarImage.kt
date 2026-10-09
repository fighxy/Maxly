package app.maxly.ui.settings

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import javax.imageio.IIOImage
import javax.imageio.ImageIO
import javax.imageio.ImageWriteParam
import kotlin.math.min

/** Готовит фото профиля: квадрат по центру не больше [SIZE] точек, JPEG. Поворот EXIF на компьютере не учитывается. */
object AvatarImage {
    private const val SIZE = 1024
    private const val QUALITY = 0.9f

    suspend fun jpeg(file: File): ByteArray? = withContext(Dispatchers.IO) {
        runCatching {
            val image = ImageIO.read(file) ?: return@runCatching null
            val side = min(image.width, image.height)
            val square = image.getSubimage((image.width - side) / 2, (image.height - side) / 2, side, side)
            val target = min(side, SIZE)
            val scaled = BufferedImage(target, target, BufferedImage.TYPE_INT_RGB)
            val canvas = scaled.createGraphics()
            canvas.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
            canvas.drawImage(square, 0, 0, target, target, null)
            canvas.dispose()
            val bytes = ByteArrayOutputStream()
            val writer = ImageIO.getImageWritersByFormatName("jpeg").next()
            val output = ImageIO.createImageOutputStream(bytes)
            writer.output = output
            val param = writer.defaultWriteParam
            if (param.canWriteCompressed()) {
                param.compressionMode = ImageWriteParam.MODE_EXPLICIT
                param.compressionQuality = QUALITY
            }
            writer.write(null, IIOImage(scaled, null, null), param)
            writer.dispose()
            output.close()
            bytes.toByteArray()
        }.getOrNull()
    }
}
