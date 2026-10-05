package app.orbitle.ui.stories

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import app.orbitle.domain.OutgoingFile
import app.orbitle.domain.OutgoingStory
import app.orbitle.ui.chat.AttachmentImporter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Выбранное фото или видео — в кэш приложения: ядро грузит историю по пути к файлу. */
object StoryFiles {
    suspend fun import(context: Context, uri: Uri): OutgoingStory? {
        val file = AttachmentImporter.import(context, listOf(uri)).firstOrNull() ?: return null
        return when (file.kind) {
            OutgoingFile.Kind.PHOTO -> OutgoingStory(file.path, isVideo = false)
            OutgoingFile.Kind.VIDEO -> OutgoingStory(file.path, isVideo = true, durationMs = durationOf(file.path))
            OutgoingFile.Kind.FILE -> null
        }
    }

    private suspend fun durationOf(path: String): Long? = withContext(Dispatchers.IO) {
        runCatching {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            } finally {
                retriever.release()
            }
        }.getOrNull()
    }
}
