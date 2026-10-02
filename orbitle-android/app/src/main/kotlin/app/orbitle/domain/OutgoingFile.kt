package app.orbitle.domain

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

    companion object {
        /** Тип вложения по MIME: картинки — фото, видео — видео, остальное — файл. */
        fun kindOf(mime: String?): Kind = when {
            mime == null -> Kind.FILE
            mime.startsWith("image/") && mime != "image/svg+xml" -> Kind.PHOTO
            mime.startsWith("video/") -> Kind.VIDEO
            else -> Kind.FILE
        }

        /** Сколько вложений уходит одним сообщением. */
        const val LIMIT = 10
    }
}
