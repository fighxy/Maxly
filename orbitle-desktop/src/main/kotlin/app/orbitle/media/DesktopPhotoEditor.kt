package app.orbitle.media

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import app.orbitle.domain.OutgoingFile
import app.orbitle.presentation.photo.*
import app.orbitle.ui.photo.PhotoEditorSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.awt.BasicStroke
import java.awt.AlphaComposite
import java.awt.Color
import java.awt.Font
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.File
import java.util.UUID
import javax.imageio.ImageIO
import kotlin.coroutines.coroutineContext
import kotlin.math.max
import kotlin.math.roundToInt

class DesktopPhotoEditor private constructor(private val file: OutgoingFile, private val original: BufferedImage) : PhotoEditorSource {
    override val size = PhotoSize(original.width, original.height)

    override suspend fun preview(edits: List<PhotoEdit>): ImageBitmap = withContext(Dispatchers.Default) {
        render(scaled(original, 1200), edits).toComposeImageBitmap()
    }

    override suspend fun export(edits: List<PhotoEdit>): OutgoingFile = withContext(Dispatchers.IO) {
        val result = render(scaled(original, 2560), edits)
        val target = File(File(File(file.path).parentFile, UUID.randomUUID().toString()), "edited.jpg")
        target.parentFile.mkdirs()
        try {
            check(ImageIO.write(result, "jpg", target)) { "JPEG encoder unavailable" }
            OutgoingFile(target.absolutePath, target.name, OutgoingFile.Kind.PHOTO, target.length(), result.width, result.height)
        } catch (e: Exception) { target.delete(); throw e }
    }

    companion object {
        suspend fun load(file: OutgoingFile): DesktopPhotoEditor = withContext(Dispatchers.IO) {
            val original = ImageIO.createImageInputStream(File(file.path)).use { input ->
                val readers = ImageIO.getImageReaders(input)
                check(readers.hasNext()) { "Unreadable image" }
                val reader = readers.next()
                try {
                    reader.input=input
                    val sampling = max(1,kotlin.math.ceil(max(reader.getWidth(0),reader.getHeight(0))/4096.0).toInt())
                    val params=reader.defaultReadParam.apply { setSourceSubsampling(sampling,sampling,0,0) }
                    reader.read(0,params) ?: error("Unreadable image")
                } finally { reader.dispose() }
            }
            DesktopPhotoEditor(file, orient(original, File(file.path)))
        }

        internal fun scaled(source: BufferedImage, limit: Int): BufferedImage {
            val scale = minOf(1.0, limit.toDouble() / max(source.width, source.height))
            val image = BufferedImage(max(1, (source.width * scale).roundToInt()), max(1, (source.height * scale).roundToInt()), BufferedImage.TYPE_INT_RGB)
            image.createGraphics().let { g ->
                try {
                    g.color = Color.WHITE; g.fillRect(0, 0, image.width, image.height)
                    g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC)
                    g.drawImage(source, 0, 0, image.width, image.height, null)
                } finally { g.dispose() }
            }
            return image
        }

        /** JPEG EXIF Orientation: ImageIO сам её не применяет. */
        private fun orient(image: BufferedImage, file: File): BufferedImage {
            val orientation = file.inputStream().use { PhotoExif.orientation(it) }
            if (orientation == 1) return image
            val swap = orientation in 5..8
            val result = BufferedImage(if (swap) image.height else image.width, if (swap) image.width else image.height, BufferedImage.TYPE_INT_RGB)
            for (y in 0 until image.height) for (x in 0 until image.width) {
                val (tx, ty) = PhotoExif.position(orientation, x, y, image.width, image.height)
                result.setRGB(tx, ty, image.getRGB(x, y))
            }
            return result
        }

        internal suspend fun render(base: BufferedImage, edits: List<PhotoEdit>): BufferedImage {
            var image = base
            var layer = BufferedImage(base.width, base.height, BufferedImage.TYPE_INT_ARGB)
            fun composite(): BufferedImage = scaled(image, max(image.width, image.height)).also { out ->
                val g = out.createGraphics(); try { g.drawImage(layer, 0, 0, null) } finally { g.dispose() }
            }
            fun transform(source: BufferedImage, edit: PhotoEdit): BufferedImage {
                val rotate = edit is PhotoEdit.Rotate
                val out = BufferedImage(if (rotate) source.height else source.width, if (rotate) source.width else source.height, source.type)
                val g = out.createGraphics()
                try {
                    g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC)
                    when (edit) {
                        is PhotoEdit.Rotate -> if (edit.clockwise) { g.translate(out.width.toDouble(), 0.0); g.rotate(Math.PI / 2) }
                            else { g.translate(0.0, out.height.toDouble()); g.rotate(-Math.PI / 2) }
                        PhotoEdit.Flip -> { g.translate(out.width.toDouble(), 0.0); g.scale(-1.0, 1.0) }
                        is PhotoEdit.Straighten -> {
                            val angle = Math.toRadians(edit.degrees.toDouble()); val c = kotlin.math.abs(kotlin.math.cos(angle)); val s = kotlin.math.abs(kotlin.math.sin(angle))
                            val scale = max(c + source.height.toDouble()/source.width*s, c + source.width.toDouble()/source.height*s)
                            g.translate(source.width/2.0, source.height/2.0); g.rotate(angle); g.scale(scale, scale); g.translate(-source.width/2.0, -source.height/2.0)
                        }
                        else -> Unit
                    }
                    g.drawImage(source, 0, 0, null)
                } finally { g.dispose() }
                return out
            }
            for (edit in edits) {
                coroutineContext.ensureActive()
                when (edit) {
                    is PhotoEdit.Crop -> {
                        val rect = edit.rect.pixels(PhotoSize(image.width, image.height))
                        image = scaled(image.getSubimage(rect.x, rect.y, rect.width, rect.height), max(rect.width, rect.height))
                        layer = BufferedImage(rect.width, rect.height, BufferedImage.TYPE_INT_ARGB).also { out ->
                            val g = out.createGraphics(); try { g.drawImage(layer, -rect.x, -rect.y, null) } finally { g.dispose() }
                        }
                    }
                    is PhotoEdit.Rotate, PhotoEdit.Flip, is PhotoEdit.Straighten -> { image = transform(image, edit); layer = transform(layer, edit) }
                    is PhotoEdit.Filter -> {
                        val row = IntArray(image.width)
                        for (y in 0 until image.height) {
                            coroutineContext.ensureActive()
                            image.getRGB(0, y, image.width, 1, row, 0, image.width)
                            for (x in row.indices) row[x] = edit.preset.pixel(row[x], edit.amount)
                            image.setRGB(0, y, image.width, 1, row, 0, image.width)
                        }
                    }
                    is PhotoEdit.Adjust -> {
                        val pixels = image.getRGB(0, 0, image.width, image.height, null, 0, image.width)
                        val adjusted = PhotoPixels.adjust(pixels, PhotoSize(image.width, image.height), edit.values)
                        image.setRGB(0, 0, image.width, image.height, adjusted, 0, image.width)
                    }
                    else -> {
                        val g = layer.createGraphics()
                        try {
                            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
                            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON)
                            val shortest = minOf(image.width, image.height).toFloat()
                            when (edit) {
                                is PhotoEdit.Stroke -> {
                                    g.color = if (edit.brush == PhotoBrush.MARKER) Color((edit.color and 0xffffff) or (100 shl 24), true) else Color(edit.color, true)
                                    if (edit.brush == PhotoBrush.ERASER) g.composite = AlphaComposite.Clear
                                    val width = edit.width * shortest
                                    g.stroke = BasicStroke(width, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
                                    val path = java.awt.geom.Path2D.Float()
                                    val first = edit.points.first()
                                    path.moveTo(first.x * image.width, first.y * image.height)
                                    edit.points.drop(1).forEach { path.lineTo(it.x * image.width, it.y * image.height) }
                                    if (edit.brush == PhotoBrush.ARROW && edit.points.size > 1) {
                                        val last = edit.points.last(); val dx = (last.x-first.x)*image.width; val dy = (last.y-first.y)*image.height
                                        val angle = kotlin.math.atan2(dy,dx); val length = max(width*4, shortest*.04f)
                                        for (side in listOf(-1,1)) { path.moveTo(last.x*image.width,last.y*image.height); path.lineTo(last.x*image.width-length*kotlin.math.cos(angle+side*.5f),last.y*image.height-length*kotlin.math.sin(angle+side*.5f)) }
                                    }
                                    if (edit.brush == PhotoBrush.BLUR) {
                                        val combined = composite(); val pixels = combined.getRGB(0,0,image.width,image.height,null,0,image.width)
                                        combined.setRGB(0,0,image.width,image.height,PhotoPixels.blur(pixels,image.width,image.height,max(2,(shortest*.012f).roundToInt())),0,image.width)
                                        g.clip = if(edit.points.size==1) java.awt.geom.Ellipse2D.Float(first.x*image.width-width/2,first.y*image.height-width/2,width,width)
                                            else (g.stroke as BasicStroke).createStrokedShape(path)
                                        g.drawImage(combined,0,0,null)
                                        continue
                                    }
                                    g.draw(path)
                                    if (edit.points.size == 1) g.fill(java.awt.geom.Ellipse2D.Float(first.x * image.width - width / 2, first.y * image.height - width / 2, width, width))
                                }
                                is PhotoEdit.Text -> {
                                    val family = when(edit.font) { PhotoFont.SERIF -> Font.SERIF; PhotoFont.MONO -> Font.MONOSPACED; else -> Font.SANS_SERIF }
                                    g.font = Font(family, if(edit.font == PhotoFont.ITALIC) Font.BOLD or Font.ITALIC else Font.BOLD, 1).deriveFont(edit.size * shortest)
                                    val lines = edit.text.split('\n')
                                    val metrics = g.fontMetrics
                                    val x = minOf(edit.point.x * image.width, max(0, image.width - lines.maxOf { metrics.stringWidth(it) }).toFloat())
                                    var y = minOf(edit.point.y * image.height, max(0, image.height - lines.size * metrics.height).toFloat()) + metrics.ascent
                                    val textWidth = lines.maxOf { metrics.stringWidth(it) }.toFloat()
                                    if (edit.style == PhotoTextStyle.SOLID || edit.style == PhotoTextStyle.TRANSLUCENT) {
                                        g.color = Color(0,0,0,if(edit.style == PhotoTextStyle.SOLID) 255 else 140)
                                        g.fill(java.awt.geom.RoundRectangle2D.Float(x-4,y-metrics.ascent-4,textWidth+8,lines.size*metrics.height+8f,8f,8f))
                                    }
                                    for (line in lines) {
                                        val offset = when(edit.alignment) { PhotoAlignment.LEFT -> 0f; PhotoAlignment.CENTER -> (textWidth-metrics.stringWidth(line))/2; PhotoAlignment.RIGHT -> textWidth-metrics.stringWidth(line) }
                                        val shape = g.font.createGlyphVector(g.fontRenderContext, line).getOutline(x+offset, y)
                                        if(edit.style == PhotoTextStyle.OUTLINE) { g.color = Color.BLACK; g.stroke = BasicStroke(max(1f, shortest * .002f), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND); g.draw(shape) }
                                        g.color = Color(edit.color, true); g.fill(shape)
                                        y += metrics.height
                                    }
                                }
                                is PhotoEdit.Shape -> {
                                    val rect = edit.rect
                                    val shape = if(edit.shape == PhotoShape.ELLIPSE) java.awt.geom.Ellipse2D.Float(rect.left*image.width,rect.top*image.height,(rect.right-rect.left)*image.width,(rect.bottom-rect.top)*image.height)
                                        else java.awt.geom.Rectangle2D.Float(rect.left*image.width,rect.top*image.height,(rect.right-rect.left)*image.width,(rect.bottom-rect.top)*image.height)
                                    g.color = Color(edit.color,true); g.stroke = BasicStroke(edit.width*shortest)
                                    if(edit.filled) g.fill(shape) else g.draw(shape)
                                }
                                else -> Unit
                            }
                        } finally { g.dispose() }
                    }
                }
            }
            return composite()
        }
    }
}
