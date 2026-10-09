package app.maxly.ui.chat

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import app.maxly.domain.OutgoingFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * Копирует выбранные в системе файлы в кэш: ядро грузит вложения по пути к файлу,
 * а доступ к content:// у приложения временный.
 */
object AttachmentImporter {
    suspend fun import(context: Context, uris: List<Uri>): List<OutgoingFile> = withContext(Dispatchers.IO) {
        uris.mapNotNull { uri -> runCatching { importOne(context, uri) }.getOrNull() }
    }

    private fun importOne(context: Context, uri: Uri): OutgoingFile? {
        val resolver = context.contentResolver
        var name: String? = null
        var size = 0L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                name = cursor.getString(0)
                if (!cursor.isNull(1)) size = cursor.getLong(1)
            }
        }
        val mime = resolver.getType(uri)
        val kind = OutgoingFile.kindOf(mime)
        val fallback = when (kind) {
            OutgoingFile.Kind.PHOTO -> "photo.jpg"
            OutgoingFile.Kind.VIDEO -> "video.mp4"
            OutgoingFile.Kind.FILE -> "file"
        }
        val safe = (name ?: uri.lastPathSegment ?: fallback).replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_").trim().ifEmpty { fallback }.take(120)
        val target = File(File(context.cacheDir, "outgoing/${UUID.randomUUID()}"), safe)
        target.parentFile?.mkdirs()
        resolver.openInputStream(uri)?.use { input -> target.outputStream().use { input.copyTo(it) } } ?: return null
        var width: Int? = null
        var height: Int? = null
        if (kind == OutgoingFile.Kind.PHOTO) {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(target.path, bounds)
            width = bounds.outWidth.takeIf { it > 0 }
            height = bounds.outHeight.takeIf { it > 0 }
        }
        return OutgoingFile(target.absolutePath, safe, kind, if (size > 0) size else target.length(), width, height)
    }
}
