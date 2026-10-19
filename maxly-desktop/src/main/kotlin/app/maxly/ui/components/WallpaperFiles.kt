package app.maxly.ui.components

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import app.maxly.domain.WallpaperScale
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Codec
import org.jetbrains.skia.Data
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.EncodedOrigin
import org.jetbrains.skia.Image
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.SamplingMode
import org.jetbrains.skia.Surface
import java.awt.FileDialog
import java.awt.Frame
import java.io.File
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Копия уже уменьшена при выборе: читается как есть. */
internal fun decodeWallpaperFile(path: String): ImageBitmap? =
    Image.makeFromEncoded(File(path).readBytes()).toComposeImageBitmap()

/** Расширения, которые предлагает окно выбора; HEIC — если его умеет прочитать декодер. */
internal val WALLPAPER_EXTENSIONS = listOf("jpg", "jpeg", "png", "webp", "heic", "heif")

/** Системное окно выбора файла «Выбрать фото для обоев»; `null` — пользователь передумал. */
internal fun pickWallpaperFile(): File? {
    val dialog = FileDialog(null as Frame?, "Фото для обоев", FileDialog.LOAD)
    dialog.setFilenameFilter { _, name -> name.substringAfterLast('.', "").lowercase() in WALLPAPER_EXTENSIONS }
    dialog.isVisible = true
    val name = dialog.file ?: return null
    return File(dialog.directory, name)
}

/**
 * Копия фото в [target]: уменьшение до [WallpaperScale.MAX_SIDE] по длинной стороне и поворот по
 * EXIF, JPEG 90. `false` — формат не читается (например, HEIC без декодера).
 */
internal fun importWallpaper(source: File, target: File): Boolean = runCatching {
    val codec = Codec.makeFromData(Data.makeFromBytes(source.readBytes()))
    // Кодек читает пиксели как они лежат в файле, без поворота: поворот делаем сами.
    val raw = Bitmap().apply { allocPixels(codec.imageInfo) }
    codec.readPixels(raw)
    val image = Image.makeFromBitmap(raw)
    val origin = codec.encodedOrigin
    val orientation = when (origin) {
        EncodedOrigin.LEFT_TOP, EncodedOrigin.RIGHT_TOP, EncodedOrigin.RIGHT_BOTTOM, EncodedOrigin.LEFT_BOTTOM -> 6
        else -> 1
    }
    val (w, h) = WallpaperScale.target(image.width, image.height)
    val (outW, outH) = WallpaperScale.oriented(w, h, orientation)
    val surface = Surface.makeRasterN32Premul(outW, outH)
    val canvas = surface.canvas
    canvas.save()
    when (origin) {
        EncodedOrigin.TOP_LEFT, EncodedOrigin.UNUSED -> Unit
        EncodedOrigin.TOP_RIGHT -> { canvas.translate(outW.toFloat(), 0f); canvas.scale(-1f, 1f) }
        EncodedOrigin.BOTTOM_RIGHT -> { canvas.translate(outW.toFloat(), outH.toFloat()); canvas.rotate(180f) }
        EncodedOrigin.BOTTOM_LEFT -> { canvas.translate(0f, outH.toFloat()); canvas.scale(1f, -1f) }
        EncodedOrigin.LEFT_TOP -> { canvas.rotate(90f); canvas.scale(1f, -1f) }
        EncodedOrigin.RIGHT_TOP -> { canvas.translate(outW.toFloat(), 0f); canvas.rotate(90f) }
        EncodedOrigin.RIGHT_BOTTOM -> { canvas.translate(outW.toFloat(), outH.toFloat()); canvas.rotate(270f); canvas.scale(1f, -1f) }
        EncodedOrigin.LEFT_BOTTOM -> { canvas.translate(0f, outH.toFloat()); canvas.rotate(270f) }
    }
    canvas.drawImageRect(
        image,
        Rect.makeWH(image.width.toFloat(), image.height.toFloat()),
        Rect.makeWH(w.toFloat(), h.toFloat()),
        SamplingMode.MITCHELL,
        Paint(),
        true,
    )
    canvas.restore()
    val bytes = surface.makeImageSnapshot().encodeToData(EncodedImageFormat.JPEG, 90)?.bytes ?: return false
    target.writeBytes(bytes)
    true
}.getOrElse { target.delete(); false }

/**
 * Окно выбора файла: jpg, png, webp и HEIC, если он читается. [onPicked] получает путь готовой
 * копии или `null`, если файл не прочитался; отмена выбора ничего не вызывает.
 */
@androidx.compose.runtime.Composable
fun rememberWallpaperPicker(photos: app.maxly.data.WallpaperPhotoSettings, onPicked: (String?) -> Unit): () -> Unit {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val callback = androidx.compose.runtime.rememberUpdatedState(onPicked)
    return {
        val source = pickWallpaperFile()
        if (source != null) scope.launch {
            val target = photos.newFile()
            val ok = withContext(kotlinx.coroutines.Dispatchers.IO) { importWallpaper(source, target) }
            callback.value(if (ok) target.absolutePath else null)
        }
    }
}
