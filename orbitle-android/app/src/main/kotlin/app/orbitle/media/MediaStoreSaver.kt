package app.orbitle.media

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import app.orbitle.domain.OrbitleError
import app.orbitle.presentation.chat.MediaSaver
import app.orbitle.presentation.chat.SavedKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Сохранение в общие папки: фото — Pictures/Orbitle, видео — Movies/Orbitle, остальное —
 * Download/Orbitle. С Android 10 через MediaStore без разрешений, раньше — файлом в папку
 * (нужно разрешение на запись, его спрашивает экран).
 */
class MediaStoreSaver(context: Context) : MediaSaver {
    private val app = context.applicationContext

    override suspend fun save(path: String, name: String, kind: SavedKind) = withContext(Dispatchers.IO) {
        val source = File(path)
        if (!source.isFile) throw OrbitleError.Rejected("Файл не найден")
        val mime = mimeOf(name, kind)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) insert(source, name, mime, kind) else legacy(source, name, mime, kind)
        } catch (e: SecurityException) {
            throw OrbitleError.Rejected("Нет доступа к памяти телефона")
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.Q)
    private fun insert(source: File, name: String, mime: String, kind: SavedKind) {
        val (collection, folder) = when (kind) {
            SavedKind.IMAGE -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) to Environment.DIRECTORY_PICTURES
            SavedKind.VIDEO -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) to Environment.DIRECTORY_MOVIES
            SavedKind.OTHER -> MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) to Environment.DIRECTORY_DOWNLOADS
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$folder/Orbitle")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = app.contentResolver
        val uri = resolver.insert(collection, values) ?: throw OrbitleError.Rejected("Не удалось сохранить")
        try {
            resolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
                ?: throw OrbitleError.Rejected("Не удалось сохранить")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun legacy(source: File, name: String, mime: String, kind: SavedKind) {
        val folder = when (kind) {
            SavedKind.IMAGE -> Environment.DIRECTORY_PICTURES
            SavedKind.VIDEO -> Environment.DIRECTORY_MOVIES
            SavedKind.OTHER -> Environment.DIRECTORY_DOWNLOADS
        }
        val dir = File(Environment.getExternalStoragePublicDirectory(folder), "Orbitle").apply { mkdirs() }
        var target = File(dir, name)
        var n = 1
        while (target.exists()) target = File(dir, "${name.substringBeforeLast('.')} (${n++})" + name.substringAfterLast('.', "").let { if (it.isEmpty()) "" else ".$it" })
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
