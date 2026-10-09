package app.maxly.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import app.maxly.domain.OutgoingFile
import app.maxly.presentation.photo.*
import app.maxly.ui.photo.PhotoEditorSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.coroutines.coroutineContext
import kotlin.math.max
import kotlin.math.roundToInt

class AndroidPhotoEditor private constructor(private val file: OutgoingFile, private val original: Bitmap) : PhotoEditorSource {
    override val size = PhotoSize(original.width, original.height)
    override suspend fun preview(edits: List<PhotoEdit>): ImageBitmap = withContext(Dispatchers.Default) {
        render(scaled(original, 1200), edits).asImageBitmap()
    }
    override suspend fun export(edits: List<PhotoEdit>): OutgoingFile = withContext(Dispatchers.IO) {
        val image = render(scaled(original, 2560), edits)
        val target = File(File(File(file.path).parentFile, UUID.randomUUID().toString()), "edited.jpg")
        target.parentFile!!.mkdirs()
        try {
            target.outputStream().use { check(image.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
            OutgoingFile(target.absolutePath, target.name, OutgoingFile.Kind.PHOTO, target.length(), image.width, image.height)
        } catch (e: Exception) { target.delete(); throw e }
        finally { image.recycle() }
    }

    companion object {
        suspend fun load(file: OutgoingFile): AndroidPhotoEditor = withContext(Dispatchers.IO) {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            check(bounds.outWidth > 0 && bounds.outHeight > 0)
            val options = BitmapFactory.Options().apply {
                while (max(bounds.outWidth, bounds.outHeight) / inSampleSize > 4096) inSampleSize *= 2
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val decoded = BitmapFactory.decodeFile(file.path, options) ?: error("Unreadable image")
            val orientation = File(file.path).inputStream().use { PhotoExif.orientation(it) }
            val matrix = Matrix().apply {
                when (orientation) {
                    2 -> setScale(-1f, 1f)
                    3 -> setRotate(180f)
                    4 -> setScale(1f, -1f)
                    5 -> { setRotate(90f); postScale(-1f, 1f) }
                    6 -> setRotate(90f)
                    7 -> { setRotate(90f); postScale(1f, -1f) }
                    8 -> setRotate(-90f)
                }
            }
            val oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
            if (oriented !== decoded) decoded.recycle()
            AndroidPhotoEditor(file, oriented)
        }

        private fun scaled(source: Bitmap, limit: Int): Bitmap {
            val scale = minOf(1f, limit.toFloat() / max(source.width, source.height))
            val copy = Bitmap.createBitmap(max(1, (source.width * scale).roundToInt()), max(1, (source.height * scale).roundToInt()), Bitmap.Config.ARGB_8888)
            Canvas(copy).apply {
                drawColor(android.graphics.Color.WHITE)
                drawBitmap(source, null, android.graphics.Rect(0, 0, copy.width, copy.height), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            }
            return copy
        }

        private suspend fun render(base: Bitmap, edits: List<PhotoEdit>): Bitmap {
            var image = base
            var layer = Bitmap.createBitmap(base.width, base.height, Bitmap.Config.ARGB_8888)
            fun composite() = image.copy(Bitmap.Config.ARGB_8888,true).also { Canvas(it).drawBitmap(layer,0f,0f,null) }
            fun transform(source: Bitmap, edit: PhotoEdit): Bitmap {
                val quarter = edit is PhotoEdit.Rotate
                val out = Bitmap.createBitmap(if(quarter) source.height else source.width, if(quarter) source.width else source.height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(out)
                when(edit) {
                    is PhotoEdit.Rotate -> if(edit.clockwise) { canvas.translate(out.width.toFloat(),0f); canvas.rotate(90f) } else { canvas.translate(0f,out.height.toFloat()); canvas.rotate(-90f) }
                    PhotoEdit.Flip -> { canvas.translate(out.width.toFloat(),0f); canvas.scale(-1f,1f) }
                    is PhotoEdit.Straighten -> {
                        val angle = Math.toRadians(edit.degrees.toDouble()); val c = kotlin.math.abs(kotlin.math.cos(angle)); val s = kotlin.math.abs(kotlin.math.sin(angle))
                        val scale = max(c+source.height.toDouble()/source.width*s,c+source.width.toDouble()/source.height*s).toFloat()
                        canvas.translate(source.width/2f,source.height/2f); canvas.rotate(edit.degrees); canvas.scale(scale,scale); canvas.translate(-source.width/2f,-source.height/2f)
                    }
                    else -> Unit
                }
                canvas.drawBitmap(source,0f,0f,Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)); source.recycle()
                return out
            }
            try {
                for (edit in edits) {
                    coroutineContext.ensureActive()
                    when (edit) {
                        is PhotoEdit.Crop -> {
                            val rect = edit.rect.pixels(PhotoSize(image.width, image.height))
                            fun cropped(source: Bitmap): Bitmap {
                                val next = Bitmap.createBitmap(rect.width,rect.height,Bitmap.Config.ARGB_8888)
                                Canvas(next).drawBitmap(source,-rect.x.toFloat(),-rect.y.toFloat(),null); source.recycle(); return next
                            }
                            image = cropped(image); layer = cropped(layer)
                        }
                        is PhotoEdit.Rotate, PhotoEdit.Flip, is PhotoEdit.Straighten -> { image = transform(image,edit); layer = transform(layer,edit) }
                        is PhotoEdit.Filter -> {
                            val row = IntArray(image.width)
                            for (y in 0 until image.height) {
                                coroutineContext.ensureActive()
                                image.getPixels(row, 0, image.width, 0, y, image.width, 1)
                                for (x in row.indices) row[x] = edit.preset.pixel(row[x], edit.amount)
                                image.setPixels(row, 0, image.width, 0, y, image.width, 1)
                            }
                        }
                        is PhotoEdit.Adjust -> {
                            val pixels = IntArray(image.width*image.height); image.getPixels(pixels,0,image.width,0,0,image.width,image.height)
                            image.setPixels(PhotoPixels.adjust(pixels,PhotoSize(image.width,image.height),edit.values),0,image.width,0,0,image.width,image.height)
                        }
                        else -> {
                            val canvas = Canvas(layer)
                            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                            val shortest = minOf(image.width, image.height).toFloat()
                            when (edit) {
                                is PhotoEdit.Stroke -> {
                                    paint.color = edit.color; paint.style = Paint.Style.STROKE
                                    if(edit.brush == PhotoBrush.MARKER) paint.alpha = 100
                                    if(edit.brush == PhotoBrush.ERASER) paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
                                    paint.strokeWidth = edit.width * shortest; paint.strokeCap = Paint.Cap.ROUND; paint.strokeJoin = Paint.Join.ROUND
                                    val first = edit.points.first()
                                    val path = Path().apply {
                                        moveTo(first.x * image.width, first.y * image.height)
                                        edit.points.drop(1).forEach { lineTo(it.x * image.width, it.y * image.height) }
                                    }
                                    if(edit.brush == PhotoBrush.ARROW && edit.points.size > 1) {
                                        val last = edit.points.last(); val angle = kotlin.math.atan2((last.y-first.y)*image.height,(last.x-first.x)*image.width)
                                        val length = max(paint.strokeWidth*4,shortest*.04f)
                                        for(side in listOf(-1,1)) { path.moveTo(last.x*image.width,last.y*image.height); path.lineTo(last.x*image.width-length*kotlin.math.cos(angle+side*.5f),last.y*image.height-length*kotlin.math.sin(angle+side*.5f)) }
                                    }
                                    if(edit.brush == PhotoBrush.BLUR) {
                                        val combined = composite(); val pixels = IntArray(image.width*image.height); combined.getPixels(pixels,0,image.width,0,0,image.width,image.height)
                                        combined.setPixels(PhotoPixels.blur(pixels,image.width,image.height,max(2,(shortest*.012f).roundToInt())),0,image.width,0,0,image.width,image.height)
                                        val mask = Path()
                                        if(edit.points.size==1) mask.addCircle(first.x*image.width,first.y*image.height,paint.strokeWidth/2,Path.Direction.CW) else paint.getFillPath(path,mask)
                                        canvas.save(); canvas.clipPath(mask); canvas.drawBitmap(combined,0f,0f,null); canvas.restore(); combined.recycle(); continue
                                    }
                                    canvas.drawPath(path, paint)
                                    if (edit.points.size == 1) { paint.style = Paint.Style.FILL; canvas.drawCircle(first.x * image.width, first.y * image.height, paint.strokeWidth / 2, paint) }
                                }
                                is PhotoEdit.Text -> {
                                    val family = when(edit.font) { PhotoFont.SERIF -> "serif"; PhotoFont.MONO -> "monospace"; else -> "sans-serif" }
                                    paint.typeface = Typeface.create(family,if(edit.font == PhotoFont.ITALIC) Typeface.BOLD_ITALIC else Typeface.BOLD); paint.textSize = edit.size * shortest
                                    val lines = edit.text.split('\n'); val metrics = paint.fontMetrics
                                    val height = metrics.descent - metrics.ascent
                                    val x = minOf(edit.point.x * image.width, max(0f, image.width - lines.maxOf { paint.measureText(it) }))
                                    var y = minOf(edit.point.y * image.height, max(0f, image.height - lines.size * height)) - metrics.ascent
                                    val textWidth = lines.maxOf { paint.measureText(it) }
                                    if(edit.style == PhotoTextStyle.SOLID || edit.style == PhotoTextStyle.TRANSLUCENT) {
                                        paint.color = android.graphics.Color.BLACK; paint.alpha = if(edit.style == PhotoTextStyle.SOLID) 255 else 140
                                        canvas.drawRoundRect(x-4,y+metrics.ascent-4,x+textWidth+4,y+metrics.ascent+lines.size*height+4,8f,8f,paint); paint.alpha = 255
                                    }
                                    for (line in lines) {
                                        val offset = when(edit.alignment) { PhotoAlignment.LEFT -> 0f; PhotoAlignment.CENTER -> (textWidth-paint.measureText(line))/2; PhotoAlignment.RIGHT -> textWidth-paint.measureText(line) }
                                        if(edit.style == PhotoTextStyle.OUTLINE) { paint.style = Paint.Style.STROKE; paint.color = android.graphics.Color.BLACK; paint.strokeWidth = max(1f, shortest * .002f); canvas.drawText(line,x+offset,y,paint) }
                                        paint.style = Paint.Style.FILL; paint.color = edit.color; canvas.drawText(line, x+offset, y, paint)
                                        y += height
                                    }
                                }
                                is PhotoEdit.Shape -> {
                                    val rect = edit.rect; paint.color = edit.color; paint.strokeWidth = edit.width*shortest; paint.style = if(edit.filled) Paint.Style.FILL else Paint.Style.STROKE
                                    if(edit.shape == PhotoShape.ELLIPSE) canvas.drawOval(rect.left*image.width,rect.top*image.height,rect.right*image.width,rect.bottom*image.height,paint)
                                    else canvas.drawRect(rect.left*image.width,rect.top*image.height,rect.right*image.width,rect.bottom*image.height,paint)
                                }
                                else -> Unit
                            }
                        }
                    }
                }
                return composite()
            } finally { image.recycle(); layer.recycle() }
        }
    }
}
