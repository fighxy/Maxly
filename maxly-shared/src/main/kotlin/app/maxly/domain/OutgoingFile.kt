package app.maxly.domain

/** Вложение, выбранное для отправки: копия файла в кэше приложения. */
data class OutgoingFile(
    val path: String,
    val name: String,
    val kind: Kind,
    val size: Long = 0,
    val width: Int? = null,
    val height: Int? = null,
) {
    enum class Kind { PHOTO, VIDEO, FILE }

    /** Гифка уходит как есть: её не открывают в редакторе и не перекодируют. */
    val isGif: Boolean get() = kind == Kind.PHOTO && name.endsWith(".gif", ignoreCase = true)

    companion object {
        /** Тип вложения по MIME: картинки — фото, видео — видео, остальное — файл. */
        fun kindOf(mime: String?): Kind = when {
            mime == null -> Kind.FILE
            mime.startsWith("image/") && mime != "image/svg+xml" -> Kind.PHOTO
            mime.startsWith("video/") -> Kind.VIDEO
            else -> Kind.FILE
        }

        /** Имя файла с расширением по MIME: `image/gif` всегда кончается на `.gif`, чтобы ядро отправило гифку. */
        fun nameFor(name: String, mime: String?): String {
            if (mime != "image/gif" || name.endsWith(".gif", ignoreCase = true)) return name
            return name.substringBeforeLast('.', name).ifEmpty { "animation" } + ".gif"
        }

        /** Сколько вложений уходит одним сообщением. */
        const val LIMIT = 10
    }
}

/** Записанное голосовое: файл на устройстве, длительность и 80 столбиков волны 0…120. */
/** Записанный кружок: квадратный MP4 (H.264/AAC), длительность и сторона кадра. */
data class VideoNoteRecording(
    val path: String,
    val durationMs: Long,
    val side: Int,
    val fileName: String = "note.mp4",
)

data class VoiceRecording(
    val path: String,
    val durationMs: Long,
    val waveform: List<Int>,
    val fileName: String = "voice.ogg",
)

/**
 * Фото, файл которого ещё надо получить (гифка из поиска): сообщение сразу встаёт в ленту с
 * [preview], [prepare] скачивает файл перед загрузкой, [onSent] — после отправки.
 */
class PreparedPhoto(
    val preview: PhotoContent,
    val prepare: suspend () -> OutgoingFile,
    val onSent: () -> Unit = {},
)
