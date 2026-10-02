package app.orbitle.ui.chat

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import app.orbitle.presentation.chat.OpenFile
import java.io.File

/** Открыть скачанный файл системным приложением через FileProvider. */
object FileOpener {
    fun open(context: Context, file: OpenFile): Boolean {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", File(file.path))
        val extension = file.name.substringAfterLast('.', "").lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            context.startActivity(Intent.createChooser(intent, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
