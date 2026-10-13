package app.maxly.domain

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

/**
 * Одна история. [media] `null`, если сервер прислал то, что клиент не умеет показать.
 * [reaction] — свой лайк (эмодзи), [settings] — биты автора: кому видна и что он выключил
 * ([StoryFlags]).
 */
data class Story(
    val id: String,
    val owner: StoryOwner,
    val timeMs: Long,
    val expiresAtMs: Long = 0,
    val audience: StoryAudience = StoryAudience.EVERYONE,
    val media: StoryMedia?,
    val reaction: String? = null,
    val settings: Int = 0,
    val viewsCount: Int = 0,
) {
    val isLiked: Boolean get() = reaction != null
    val canLike: Boolean get() = settings and StoryFlags.OFF_REACT == 0
    val canReply: Boolean get() = settings and StoryFlags.OFF_REPLY == 0
    val canOpenProfile: Boolean get() = settings and StoryFlags.OFF_MENU_PROFILE == 0
    val canHideAuthor: Boolean get() = settings and StoryFlags.OFF_MENU_HIDE_AUTHOR == 0
    val canDownload: Boolean get() = settings and StoryFlags.OFF_MENU_DOWNLOAD == 0
    val canReport: Boolean get() = settings and StoryFlags.OFF_MENU_REPORT == 0
}

/** Биты `settings` истории (как у веб-клиента Max): что автор выключил у этой истории. */
object StoryFlags {
    const val VISIBLE_FOR_CONTACTS = 2
    const val OFF_REACT = 4
    const val OFF_REPLY = 8
    const val OFF_MENU_PROFILE = 16
    const val OFF_MENU_HIDE_AUTHOR = 32
    const val OFF_MENU_DOWNLOAD = 64
    const val OFF_MENU_REPORT = 128

    /** Лайк кнопки-сердечка. */
    const val HEART = "❤️"
}

/** Файл новой истории на устройстве: фото или видео, у видео — длительность, если известна. */
data class OutgoingStory(val path: String, val isVideo: Boolean, val durationMs: Long? = null)

/** Страница своего архива историй (219): [marker] `null` — дальше страниц нет. */
data class StoryArchive(val stories: List<Story>, val marker: Long?)
