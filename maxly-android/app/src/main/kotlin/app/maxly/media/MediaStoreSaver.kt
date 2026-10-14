package app.maxly.media

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import app.maxly.domain.MaxlyError
import app.maxly.presentation.chat.MediaSaver
import app.maxly.presentation.chat.SaveNaming
import app.maxly.presentation.chat.SavedKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Сохранение в «Загрузки» телефона, в Download/Maxly: фото, видео, файлы и голосовые. Фото и
 * видео оттуда видны и в галерее. Фото в WebP и HEIC сохраняются в JPEG. С Android 10 через
 * MediaStore без разрешений, раньше — файлом в папку (нужно разрешение на запись, его спрашивает
 * экран).
 */
class MediaStoreSaver(context: Context) : MediaSaver {
    private val app = context.applicationContext

    override fun place(kind: SavedKind) = "«Загрузки»"

    override suspend fun save(path: String, name: String, kind: SavedKind, directory: String?) = withContext(Dispatchers.IO) {
        val original = File(path)
        if (!original.isFile) throw MaxlyError.Rejected("Файл не найден")
        val jpeg = if (kind == SavedKind.IMAGE && SaveNaming.needsTranscode(name)) toJpeg(original) else null
        val source = jpeg ?: original
        val saved = SaveNaming.safe(if (jpeg != null) SaveNaming.withExtension(name, "jpg") else name)
        try {
            val mime = mimeOf(saved, kind)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) insert(source, saved, mime) else legacy(source, saved, mime)
        } catch (e: SecurityException) {
            throw MaxlyError.Rejected("Нет доступа к памяти телефона")
        } finally {
            jpeg?.delete()
        }
    }

    /** WebP или HEIC в JPEG во временном файле; null — если Android не прочитал картинку. */
    private fun toJpeg(source: File): File? {
        val decoded = BitmapFactory.decodeFile(source.path) ?: return null
        val opaque = if (decoded.hasAlpha()) {
            Bitmap.createBitmap(decoded.width, decoded.height, Bitmap.Config.ARGB_8888).also {
                Canvas(it).apply {
                    drawColor(Color.WHITE)
                    drawBitmap(decoded, 0f, 0f, null)
                }
                decoded.recycle()
            }
        } else {
            decoded
        }
        val target = File(app.cacheDir, "save-${System.nanoTime()}.jpg")
        return try {
            target.outputStream().use { opaque.compress(Bitmap.CompressFormat.JPEG, 95, it) }
            target
        } catch (e: Exception) {
            target.delete()
            null
        } finally {
            opaque.recycle()
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.Q)
    private fun insert(source: File, name: String, mime: String) {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Maxly")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = app.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
            ?: throw MaxlyError.Rejected("Не удалось сохранить")
        try {
            resolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
                ?: throw MaxlyError.Rejected("Не удалось сохранить")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun legacy(source: File, name: String, mime: String) {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Maxly").apply { mkdirs() }
        val target = File(dir, SaveNaming.freeName(name) { File(dir, it).exists() })
        source.copyTo(target)
        MediaScannerConnection.scanFile(app, arrayOf(target.absolutePath), arrayOf(mime), null)
    }

    private fun mimeOf(name: String, kind: SavedKind): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: when (kind) {
            SavedKind.IMAGE -> "image/jpeg"
            SavedKind.VIDEO -> "video/mp4"
            SavedKind.OTHER -> "application/octet-stream"
        }
    }
}
