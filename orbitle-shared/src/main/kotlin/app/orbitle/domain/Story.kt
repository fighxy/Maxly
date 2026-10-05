package app.orbitle.domain

/** Чья история: человек, группа или канал. Лента собирает истории по владельцам. */
data class StoryOwner(val id: String, val type: Type = Type.USER) {
    enum class Type(val code: Int) { USER(0), CHAT(1), CHANNEL(2) }
}

/**
 * Кольцо владельца в ленте: сколько у него историй и сколько из них уже просмотрено.
 * [name] и [avatarUrl] — из профиля владельца, пустые, если он неизвестен.
 */
data class StoryRing(
    val owner: StoryOwner,
    val name: String,
    val avatarUrl: String?,
    val updatedAtMs: Long,
    val total: Int,
    val read: Int,
    val expiresAtMs: Long = 0,
) {
    val unread: Int get() = (total - read).coerceAtLeast(0)
    val hasUnread: Boolean get() = unread > 0
    /** Историй не осталось: кольцо убирается. */
    val isEmpty: Boolean get() = total <= 0
}

/** Кто видит опубликованную историю. */
enum class StoryAudience(val code: Int) { EVERYONE(1), CONTACTS(2) }

/** Фото или видео истории: [url] — адрес картинки или MP4, у видео [thumbnailUrl] — обложка. */
data class StoryMedia(
    val isVideo: Boolean,
    val url: String,
    val thumbnailUrl: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val durationMs: Long? = null,
)

/** Одна история. [media] `null`, если сервер прислал то, что клиент не умеет показать. */
data class Story(
    val id: String,
    val owner: StoryOwner,
    val timeMs: Long,
    val expiresAtMs: Long = 0,
    val audience: StoryAudience = StoryAudience.EVERYONE,
    val media: StoryMedia?,
)

/** Файл новой истории на устройстве: фото или видео, у видео — длительность, если известна. */
data class OutgoingStory(val path: String, val isVideo: Boolean, val durationMs: Long? = null)
