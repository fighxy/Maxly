package app.maxly.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import app.maxly.domain.WallpaperScale
import java.io.File
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Копия уже уменьшена при выборе: читается как есть. */
internal fun decodeWallpaperFile(path: String): ImageBitmap? = BitmapFactory.decodeFile(path)?.asImageBitmap()

/**
 * Копия фото из системного выбора в [target]: прореживание при чтении, точное уменьшение до
 * [WallpaperScale.MAX_SIDE] по длинной стороне и поворот по EXIF, JPEG 90. Разрешение на
 * хранилище не нужно: системный выбор фото выдаёт доступ к одному файлу.
 */
internal fun importWallpaper(context: Context, uri: Uri, target: File): Boolean = runCatching {
    val resolver = context.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return false
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false
    val orientation = resolver.openInputStream(uri)?.use {
        ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    } ?: ExifInterface.ORIENTATION_NORMAL
    val options = BitmapFactory.Options().apply { inSampleSize = WallpaperScale.sampleSize(bounds.outWidth, bounds.outHeight) }
    val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return false
    val (w, h) = WallpaperScale.target(decoded.width, decoded.height)
    val matrix = Matrix().apply {
        postScale(w / decoded.width.toFloat(), h / decoded.height.toFloat())
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { postRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { postRotate(270f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> postRotate(270f)
        }
    }
    val result = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    target.outputStream().use { result.compress(Bitmap.CompressFormat.JPEG, 90, it) }
    if (result !== decoded) result.recycle()
    decoded.recycle()
    true
}.getOrElse { target.delete(); false }

/**
 * Системный выбор фото (Photo Picker, без разрешения на хранилище). [onPicked] получает путь
 * готовой копии или `null`, если фото не прочиталось; отмена выбора ничего не вызывает.
 */
@androidx.compose.runtime.Composable
fun rememberWallpaperPicker(photos: app.maxly.data.WallpaperPhotoSettings, onPicked: (String?) -> Unit): () -> Unit {
    val context = androidx.compose.ui.platform.LocalContext.current.applicationContext
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val callback = androidx.compose.runtime.rememberUpdatedState(onPicked)
    val launcher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri != null) scope.launch {
            val target = photos.newFile()
            val ok = withContext(kotlinx.coroutines.Dispatchers.IO) { importWallpaper(context, uri, target) }
            callback.value(if (ok) target.absolutePath else null)
        }
    }
    return {
        launcher.launch(
            androidx.activity.result.PickVisualMediaRequest(
                androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly,
            ),
        )
    }
}
