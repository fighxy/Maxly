package app.orbitle.domain

/**
 * Прочитавший сообщение в группе. [emoji] — его реакция на это сообщение: такие идут в списке первыми.
 * Пустое имя — профиль не загрузился.
 */
data class MessageReader(
    val userId: String,
    val name: String,
    val avatarUrl: String? = null,
    val emoji: String? = null,
)
