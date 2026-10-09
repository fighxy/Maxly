package app.maxly.presentation.stories

import app.maxly.domain.StoryRing
import app.maxly.presentation.chatlist.ChatAvatar

/** Подписи и аватары историй, общие для Android и десктопа. */
object StoryText {
    const val YOUR_STORY = "Ваша история"
    const val NO_NAME = "Без имени"

    /** Больше этого сегментов кольцо не рисует: при длинной ленте они слились бы в линию. */
    const val MAX_SEGMENTS = 30

    fun avatar(ring: StoryRing): ChatAvatar = avatar(ring.owner.id, ring.name, ring.avatarUrl)

    /** Аватар по id, имени и адресу фото: свой для плитки «Ваша история», чужой для кольца. */
    fun avatar(id: String, name: String, avatarUrl: String?): ChatAvatar {
        val initials = ChatAvatar.initials(name.ifBlank { NO_NAME })
        val url = avatarUrl?.takeIf { it.isNotBlank() }
        return ChatAvatar(if (url != null) ChatAvatar.Kind.Photo(url, initials) else ChatAvatar.Kind.Initials(initials), ChatAvatar.colorIndex(id))
    }

    fun title(ring: StoryRing, own: Boolean): String = if (own) YOUR_STORY else ring.name.ifBlank { NO_NAME }

    /** Сколько сегментов у кольца и сколько из них уже просмотрено. */
    fun segments(ring: StoryRing): Pair<Int, Int> {
        val total = ring.total.coerceIn(1, MAX_SEGMENTS)
        return total to ring.read.coerceIn(0, total)
    }

    /** «только что», «5 мин назад», «3 ч назад»; старше суток — «вчера». */
    fun ago(timeMs: Long, nowMs: Long): String {
        val minutes = ((nowMs - timeMs) / 60_000).coerceAtLeast(0)
        return when {
            timeMs <= 0 -> ""
            minutes < 1 -> "только что"
            minutes < 60 -> "$minutes мин назад"
            minutes < 24 * 60 -> "${minutes / 60} ч назад"
            else -> "вчера"
        }
    }

    /** Подпись прогресса публикации. */
    fun publishing(progress: Float): String = "Публикация… ${(progress.coerceIn(0f, 1f) * 100).toInt()}%"
}
