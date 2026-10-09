package app.maxly.presentation.chat

/**
 * Углы пузыря в dp. Хвоста нет.
 * Углы 18. У последнего сообщения серии нижний угол со стороны автора — 6.
 * Если следом идёт сообщение того же автора, этот угол тоже 18.
 * Сообщения одного автора склеиваются, если между ними не больше 15 минут.
 */
data class BubbleCorners(
    val topStart: Float,
    val topEnd: Float,
    val bottomEnd: Float,
    val bottomStart: Float,
) {
    companion object {
        const val LARGE = 18f
        const val SMALL = 6f
        const val ATTACH_WINDOW_MS = 15 * 60 * 1000L

        /** Потолок ширины пузыря на десктопе, в dp. На широкой панели пузырь остаётся узким. */
        const val DESKTOP_MAX_DP = 430f

        fun of(outgoing: Boolean, joinsPrevious: Boolean, joinsNext: Boolean): BubbleCorners {
            // joinsPrevious на радиус не влияет: верх всегда крупный, хвоста сверху нет.
            val bottomAuthor = if (joinsNext) LARGE else SMALL
            return if (outgoing) {
                BubbleCorners(topStart = LARGE, topEnd = LARGE, bottomEnd = bottomAuthor, bottomStart = LARGE)
            } else {
                BubbleCorners(topStart = LARGE, topEnd = LARGE, bottomEnd = LARGE, bottomStart = bottomAuthor)
            }
        }
    }
}

/** Два обычных сообщения одного автора в одном дне и в пределах окна склейки. */
fun messagesAttach(
    authorId: String,
    timeMs: Long,
    otherAuthorId: String?,
    otherTimeMs: Long?,
    sameDay: Boolean,
): Boolean {
    if (!sameDay || otherAuthorId == null || otherTimeMs == null) return false
    if (authorId != otherAuthorId) return false
    return kotlin.math.abs(otherTimeMs - timeMs) <= BubbleCorners.ATTACH_WINDOW_MS
}
