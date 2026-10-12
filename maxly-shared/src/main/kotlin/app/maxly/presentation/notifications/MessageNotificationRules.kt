package app.maxly.presentation.notifications

import app.maxly.domain.ChatType
import app.maxly.domain.IncomingMessageNotice

/**
 * Уведомление о новом сообщении, пока приложение не на экране: показывать ли его и что в нём.
 * Те же правила, что на iOS.
 *
 * Не показываем, когда приложение на экране (сообщение и так видно), когда уведомления
 * выключены в настройках и в чатах «без звука». Заголовок — чат, в группе подзаголовок —
 * автор, текст — сообщение или подпись вложения, как в списке чатов.
 */
object MessageNotificationRules {
    data class Content(val title: String, val subtitle: String?, val body: String)

    /** Самое длинное тело уведомления: дальше система всё равно обрезает. */
    const val BODY_LIMIT = 300
    /** Заголовок группы или канала без названия. */
    const val UNTITLED_CHAT = "Чат"
    /** Личный чат без названия и без имени автора. */
    const val UNKNOWN_AUTHOR = "Участник"
    /** Сообщение без текста и без понятного вложения. */
    const val EMPTY_BODY = "Сообщение"

    fun content(notice: IncomingMessageNotice, appActive: Boolean, enabled: Boolean): Content? {
        if (!enabled || appActive || notice.isMuted) return null
        val author = notice.authorName.trim()
        val chat = notice.chatTitle.trim()
        val text = notice.text.trim()
        val body = if (text.isEmpty()) notice.media.trim().ifEmpty { EMPTY_BODY } else text.take(BODY_LIMIT)
        return when (notice.chatType) {
            ChatType.PRIVATE -> Content(chat.ifEmpty { author.ifEmpty { UNKNOWN_AUTHOR } }, null, body)
            ChatType.GROUP -> {
                val title = chat.ifEmpty { UNTITLED_CHAT }
                Content(title, author.takeIf { it.isNotEmpty() && it != title }, body)
            }
            ChatType.CHANNEL -> Content(chat.ifEmpty { UNTITLED_CHAT }, null, body)
        }
    }
}
