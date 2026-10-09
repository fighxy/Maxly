package app.maxly.domain

/**
 * Прочитавший сообщение в группе. [emoji] — его реакция на это сообщение: такие идут в списке первыми.
 * [readMarkMs] — его отметка прочтения (мс): время последнего прочитанного им сообщения, не момент
 * чтения; `null`, если он в списке только из-за реакции. Пустое имя — профиль не загрузился.
 */
data class MessageReader(
    val userId: String,
    val name: String,
    val avatarUrl: String? = null,
    val emoji: String? = null,
    val readMarkMs: Long? = null,
)
