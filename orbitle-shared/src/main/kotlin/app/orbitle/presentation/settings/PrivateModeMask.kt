package app.orbitle.presentation.settings

import app.orbitle.domain.ChatType
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListItem
import app.orbitle.domain.MessageMediaKind

/**
 * Во что приватный режим превращает строки и сообщения. Меняется только то, что видно:
 * id, время, статусы и счётчики остаются, чтобы списки и лента работали как обычно.
 */
object PrivateModeMask {
    const val SENT_TEXT = "Вы отправили сообщение"
    const val RECEIVED_TEXT = "Вы получили сообщение"
    /** Текст черновика в строке чата: «Черновик: скрыт». */
    const val DRAFT_TEXT = "скрыт"
    const val CONTACT_TITLE = "Контакт"
    const val HIDDEN_TEXT = "Сообщение скрыто"
    const val REVEAL_HINT = "Нажмите на сообщение, чтобы просмотреть исходное содержимое"
    /** Сколько открытое касанием сообщение остаётся видимым. */
    const val REVEAL_MILLIS = 15_000L

    fun messageText(outgoing: Boolean): String = if (outgoing) SENT_TEXT else RECEIVED_TEXT

    /** Общий заголовок чата по типу. «Избранное» ничего не выдаёт и остаётся. */
    fun chatTitle(type: ChatType, isSavedMessages: Boolean = false): String = when {
        isSavedMessages -> ChatListFormatter.SAVED_MESSAGES_TITLE
        type == ChatType.PRIVATE -> "Личный чат"
        type == ChatType.GROUP -> "Групповой чат"
        else -> "Канал"
    }

    fun callTitle(isGroup: Boolean): String = if (isGroup) "Групповой звонок" else "Звонок"

    /** Однотонный круг того же цвета без фото и букв. Значок «Избранного» остаётся. */
    fun avatar(avatar: ChatAvatar): ChatAvatar = when (avatar.kind) {
        ChatAvatar.Kind.SavedMessages -> avatar
        else -> ChatAvatar(ChatAvatar.Kind.Initials(""), avatar.colorIndex)
    }

    /** Строка списка без имени, аватара, автора, текста и миниатюры. */
    fun item(item: ChatListItem): ChatListItem {
        val title = chatTitle(item.type, item.avatar.kind == ChatAvatar.Kind.SavedMessages)
        // Своё последнее сообщение: у него статус доставки или автор «Вы».
        val outgoing = item.delivery != null || item.sender == "Вы"
        val preview = when (item.previewStyle) {
            ChatListItem.PreviewStyle.MESSAGE -> when (item.media) {
                MessageMediaKind.CALL -> callTitle(false)
                MessageMediaKind.GROUP_CALL -> callTitle(true)
                else -> messageText(outgoing)
            }
            ChatListItem.PreviewStyle.DRAFT -> DRAFT_TEXT
            // «печатает…» и «Нет сообщений» имён не содержат.
            ChatListItem.PreviewStyle.TYPING, ChatListItem.PreviewStyle.EMPTY -> item.preview
        }
        val masked = item.copy(
            title = title,
            avatar = avatar(item.avatar),
            isOnline = false,
            isVerified = false,
            isBot = false,
            sender = null,
            preview = preview,
            media = null,
            thumbnailUrl = null,
            isForwarded = false,
        )
        return masked.copy(accessibilityLabel = spoken(masked))
    }

    /** Заголовок чата: общее название по типу и круг без букв; подпись («в сети») остаётся. */
    fun header(header: app.orbitle.presentation.chat.ChatHeaderUi): app.orbitle.presentation.chat.ChatHeaderUi =
        header.copy(title = chatTitle(header.type, header.isSavedMessages), avatar = avatar(header.avatar), isVerified = false)

    /** Подпись-заглушка сообщения. Звонок остаётся звонком, но без исхода и длительности. */
    fun messageText(message: app.orbitle.domain.Message, outgoing: Boolean): String =
        message.content.call?.let { callTitle(it.isGroup) } ?: messageText(outgoing)

    /** Текст панели ответа и правки над полем ввода: правится всегда своё, ответ — скрыт. */
    fun panelText(message: app.orbitle.domain.Message, editing: Boolean): String =
        message.content.call?.let { callTitle(it.isGroup) } ?: if (editing) SENT_TEXT else HIDDEN_TEXT

    /**
     * Пузырь ленты: только общая подпись, время и статус. Автор остаётся id, по нему склеиваются
     * пузыри подряд, но имени и фото нет: аватар — однотонный круг.
     */
    fun bubble(item: app.orbitle.presentation.chat.ChatItem.Bubble): app.orbitle.presentation.chat.ChatItem.Bubble {
        val message = item.message
        return item.copy(
            message = app.orbitle.domain.Message(
                id = message.id,
                chatId = message.chatId,
                authorId = message.authorId,
                text = messageText(message, item.outgoing),
                timeMs = message.timeMs,
                status = message.status,
                isRead = message.isRead,
                isService = message.isService,
            ),
            authorName = null,
            avatar = item.avatar?.let(::avatar),
            comments = null,
        )
    }

    private fun spoken(item: ChatListItem): String {
        val parts = mutableListOf(item.title)
        if (item.isPinned) parts += "закреплён"
        if (item.isMuted) parts += "без звука"
        parts += if (item.previewStyle == ChatListItem.PreviewStyle.DRAFT) "черновик скрыт" else item.preview
        if (item.time.isNotEmpty()) parts += item.time
        if (item.unreadCount > 0) parts += ChatListFormatter.unreadPhrase(item.unreadCount)
        if (item.hasMention) parts += "есть упоминание"
        return parts.joinToString(", ")
    }
}
