package app.orbitle.domain

/** Карточка профиля: собеседник, бот, «Избранное», группа или канал. */
data class ChatProfile(
    val kind: Kind,
    val chatId: String,
    val title: String = "",
    val avatarUrl: String? = null,
    val peerId: String? = null,
    val description: String? = null,
    /** Публичная ссылка: `https://max.ru/name`. */
    val link: String? = null,
    val phone: String? = null,
    val isOnline: Boolean = false,
    val lastSeenMs: Long = 0,
    val isOfficial: Boolean = false,
    val isPublic: Boolean = false,
    val participants: Int? = null,
    val commands: List<BotCommand> = emptyList(),
    /** Родные комментарии канала (опция `COMMENTS`); `null` — карточка не сказала. */
    val commentsEnabled: Boolean? = null,
) {
    enum class Kind { USER, BOT, SAVED, GROUP, CHANNEL }

    data class BotCommand(val name: String, val description: String?)
}

/** Вкладки общих медиа и типы вложений сервера для каждой. */
enum class SharedMediaTab(val title: String, val attachTypes: List<String>) {
    MEDIA("Медиа", listOf("PHOTO", "VIDEO")),
    FILES("Файлы", listOf("FILE")),
    LINKS("Ссылки", listOf("SHARE")),
    VOICE("Голосовые", listOf("AUDIO")),
}
