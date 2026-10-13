package app.maxly.ui.chat

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maxly.presentation.chat.ChatMedia
import app.maxly.presentation.chat.SavedKind
import app.maxly.presentation.chat.ShareFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Системное окно «Поделиться» с фото или видео из просмотра. */
object ShareSender {
    /**
     * Файл из кэша копируется под понятным именем («Maxly 2026-10-01 14.05.33.jpg») в папку
     * для отправки — получатель видит имя и тип — и уходит в окно выбора приложения.
     */
    suspend fun share(context: Context, file: ShareFile): Boolean {
        val copy = withContext(Dispatchers.IO) {
            val folder = File(context.cacheDir, "files/share").apply { mkdirs() }
            folder.listFiles()?.forEach { it.delete() }
            File(file.path).copyTo(File(folder, file.name), overwrite = true)
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", copy)
        val mime = when (file.kind) {
            SavedKind.IMAGE -> "image/*"
            SavedKind.VIDEO -> "video/mp4"
            SavedKind.OTHER -> "application/octet-stream"
        }
        val intent = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newRawUri(file.name, uri)
        return try {
            context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}

/** Скачанный для «Поделиться» файл уходит в системное окно, как только готов. */
@Composable
fun ShareFileEffect(media: ChatMedia) {
    val context = LocalContext.current
    val state by media.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.shareFile) {
        val file = state.shareFile ?: return@LaunchedEffect
        media.consumeShareFile()
        runCatching { ShareSender.share(context, file) }
    }
}
