package app.orbitle.presentation.chatlist

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.presentation.common.TypingText
import app.orbitle.domain.DeliveryState
import app.orbitle.domain.MessageMediaKind
import app.orbitle.domain.SavedMessagesWelcome
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Аватар строки: фото, инициалы на цветном круге или значок «Избранного». */
data class ChatAvatar(val kind: Kind, val colorIndex: Int) {
    sealed interface Kind {
        data class Initials(val text: String) : Kind
        data class Photo(val url: String, val initials: String) : Kind
        data object SavedMessages : Kind
    }

    val initials: String
        get() = when (kind) {
            is Kind.Initials -> kind.text
            is Kind.Photo -> kind.initials
            Kind.SavedMessages -> ""
        }

    companion object {
        const val PALETTE_SIZE = 7

        /** Цвет по id: у числовых — остаток от деления, иначе сумма символов. */
        fun colorIndex(id: String): Int {
            // Как у iOS: модуль числа, а не floorMod, чтобы цвета совпадали на обеих платформах.
            id.toLongOrNull()?.let { return (kotlin.math.abs(it % PALETTE_SIZE)).toInt() }
            var sum = 0
            for (ch in id) sum = (sum + ch.code) and 0x7fff_ffff
            return sum % PALETTE_SIZE
        }

        /** Первые буквы двух первых слов. */
        fun initials(title: String): String {
            val words = title.split(Regex("[\\s-]+")).filter { it.isNotEmpty() }.take(2)
            val letters = words.mapNotNull { w -> w.firstOrNull { it.isLetterOrDigit() } }.joinToString("")
            if (letters.isNotEmpty()) return letters.uppercase()
            return title.take(1).uppercase()
        }
    }
}

sealed interface ChatBadge {
    data class Count(val text: String) : ChatBadge
    data object Dot : ChatBadge
}

/** Готовая строка списка чатов. */
data class ChatListItem(
    val id: String,
    val title: String,
    val type: ChatType,
    val avatar: ChatAvatar,
    val isOnline: Boolean,
    val isMuted: Boolean,
    val isVerified: Boolean,
    val isBot: Boolean,
    val isPinned: Boolean,
    /** «Вы» или имя автора в группах. */
    val sender: String?,
    val preview: String,
    val previewStyle: PreviewStyle,
    val media: MessageMediaKind?,
    val thumbnailUrl: String?,
    val delivery: DeliveryState?,
    val time: String,
    val unreadCount: Int,
    val badge: ChatBadge?,
    val badgeMuted: Boolean,
    val hasMention: Boolean,
    val isForwarded: Boolean,
    val accessibilityLabel: String,
    /** Есть что читать: счётчик или ручная пометка. */
    val isUnread: Boolean = false,
    /** Собеседник личного чата: по нему находится кольцо историй. */
    val peerId: String? = null,
    /**
     * В строке кнопка «Открыть»: личный чат с ботом и [Chat.hasWebApp].
     * Касание кнопки открывает мини-приложение, касание остальной строки — чат.
     */
    val openApp: Boolean = false,
) {
    enum class PreviewStyle { MESSAGE, DRAFT, TYPING, EMPTY }

    /** Скрепка видна у закреплённых без бейджа. */
    val showsPin: Boolean get() = isPinned && badge == null && !hasMention
}

/** Строки списка чатов: время, превью, отправитель, бейджи — как в iOS-версии. */
class ChatListFormatter(private val zone: ZoneId = ZoneId.systemDefault()) {

    fun item(chat: Chat, nowMs: Long, typing: List<app.orbitle.domain.Typist> = emptyList(), showDraft: Boolean = true): ChatListItem {
        val title = title(chat)
        var style = ChatListItem.PreviewStyle.MESSAGE
        var sender: String? = null
        var media: MessageMediaKind? = null
        var thumbnail: String? = null
        val draftText = if (showDraft) chat.draft?.let { singleLine(it.text) }.orEmpty() else ""
        val text: String
        val typingLine = if (chat.isSavedMessages) null else TypingText.of(typing, chat.type)
        if (typingLine != null) {
            style = ChatListItem.PreviewStyle.TYPING
            text = typingLine
        } else if (draftText.isNotEmpty()) {
            style = ChatListItem.PreviewStyle.DRAFT
            text = draftText
        } else if (SavedMessagesWelcome.matches(chat.id, chat.preview)) {
            // Единственное сообщение «Избранного» — служебное приветствие: как в пустом чате.
            style = ChatListItem.PreviewStyle.EMPTY
            text = SAVED_MESSAGES_EMPTY
        } else {
            var body = singleLine(chat.preview.orEmpty())
            media = chat.lastMessage?.media
            thumbnail = chat.lastMessage?.thumbnailUrl
            if (body.isEmpty()) {
                body = when {
                    media != null -> mediaLabel(media)
                    chat.lastMessageId == null -> {
                        style = ChatListItem.PreviewStyle.EMPTY
                        if (chat.isSavedMessages) SAVED_MESSAGES_EMPTY else "Нет сообщений"
                    }
                    else -> "Вложение"
                }
            }
            text = body
            sender = senderName(chat)
        }
        val delivery = delivery(chat, style)
        val time = timeLabel(if (style == ChatListItem.PreviewStyle.DRAFT) chat.activityMs else chat.updatedAtMs, nowMs)
        val badge = when {
            chat.unreadCount > 0 -> ChatBadge.Count(compactCount(chat.unreadCount))
            chat.isMarkedUnread -> ChatBadge.Dot
            else -> null
        }
        val item = ChatListItem(
            id = chat.id,
            title = title,
            type = chat.type,
            avatar = avatar(chat, title),
            isOnline = chat.type == ChatType.PRIVATE && chat.isOnline && !chat.isBot && !chat.isSavedMessages,
            isMuted = chat.isMuted,
            isVerified = chat.isVerified,
            isBot = chat.isBot,
            isPinned = chat.isPinned,
            sender = sender,
            preview = text,
            previewStyle = style,
            media = if (style == ChatListItem.PreviewStyle.MESSAGE) media else null,
            thumbnailUrl = if (style == ChatListItem.PreviewStyle.MESSAGE) thumbnail else null,
            delivery = delivery,
            time = time,
            unreadCount = maxOf(chat.unreadCount, 0),
            badge = badge,
            badgeMuted = chat.isMuted,
            hasMention = chat.unreadMentions > 0,
            isForwarded = style == ChatListItem.PreviewStyle.MESSAGE && chat.lastMessage?.isForwarded == true,
            accessibilityLabel = "",
            isUnread = chat.isUnread,
            peerId = chat.peerId.takeIf { chat.type == ChatType.PRIVATE && !chat.isSavedMessages && it != "0" },
            openApp = chat.type == ChatType.PRIVATE && chat.isBot && chat.hasWebApp && !chat.isSavedMessages,
        )
        return item.copy(accessibilityLabel = spoken(item, chat))
    }

    fun title(chat: Chat): String {
        if (chat.isSavedMessages) return SAVED_MESSAGES_TITLE
        val title = chat.title.trim()
        if (title.isNotEmpty()) return title
        return when (chat.type) {
            ChatType.PRIVATE -> if (chat.isBot) "Бот" else "Личный чат"
            ChatType.GROUP -> "Группа"
            ChatType.CHANNEL -> "Канал"
        }
    }

    /** «Вы» или имя автора — только в группах. */
    fun senderName(chat: Chat): String? {
        if (chat.type != ChatType.GROUP) return null
        val last = chat.lastMessage ?: return null
        if (last.isOutgoing) return "Вы"
        return last.authorName?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun avatar(chat: Chat, title: String): ChatAvatar {
        val color = ChatAvatar.colorIndex(chat.id)
        if (chat.isSavedMessages) return ChatAvatar(ChatAvatar.Kind.SavedMessages, color)
        val initials = ChatAvatar.initials(title)
        val url = chat.avatarUrl
        return if (url != null) ChatAvatar(ChatAvatar.Kind.Photo(url, initials), color) else ChatAvatar(ChatAvatar.Kind.Initials(initials), color)
    }

    /** Галочки только у своих сообщений, не в каналах и не в «Избранном». */
    private fun delivery(chat: Chat, style: ChatListItem.PreviewStyle): DeliveryState? {
        if (style != ChatListItem.PreviewStyle.MESSAGE || chat.type == ChatType.CHANNEL || chat.isSavedMessages) return null
        val last = chat.lastMessage ?: return null
        if (!last.isOutgoing) return null
        return last.delivery ?: DeliveryState.SENT
    }

    /** `HH:mm` сегодня, «вчера», день недели в пределах недели, «5 мар» в этом году, иначе дата. */
    fun timeLabel(ms: Long, nowMs: Long): String {
        if (ms <= 0) return ""
        val date = Instant.ofEpochMilli(ms).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val days = ChronoUnit.DAYS.between(date.toLocalDate(), now.toLocalDate())
        return when {
            days == 0L -> "%02d:%02d".format(date.hour, date.minute)
            days == 1L -> "вчера"
            days in 2..6 -> WEEKDAYS[date.dayOfWeek.value - 1]
            days > 0 && date.year == now.year -> "${date.dayOfMonth} ${MONTHS[date.monthValue - 1]}"
            // Прошлые годы и время из будущего (часы сервера и телефона расходятся).
            else -> "%02d.%02d.%04d".format(date.dayOfMonth, date.monthValue, date.year)
        }
    }

    companion object {
        const val SAVED_MESSAGES_TITLE = "Избранное"
        const val SAVED_MESSAGES_EMPTY = "Сохраните что-нибудь"
        /** Понедельник первый. */
        private val WEEKDAYS = listOf("пн", "вт", "ср", "чт", "пт", "сб", "вс")
        private val MONTHS = listOf("янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек")

        fun badge(count: Int): String? = if (count > 0) compactCount(count) else null

        /** `999`, `1.2K`, `12K`, `100K`, `1.5M`: десятые отбрасываются, а не округляются. */
        fun compactCount(count: Int): String {
            val value = maxOf(count, 0)
            fun scaled(divisor: Int, suffix: String): String {
                val tenths = value / (divisor / 10)
                val whole = tenths / 10
                val fraction = tenths % 10
                return if (fraction == 0 || whole >= 100) "$whole$suffix" else "$whole.$fraction$suffix"
            }
            return when {
                value < 1_000 -> "$value"
                value < 1_000_000 -> scaled(1_000, "K")
                else -> scaled(1_000_000, "M")
            }
        }

        fun mediaLabel(kind: MessageMediaKind): String = when (kind) {
            MessageMediaKind.PHOTO -> "Фотография"
            MessageMediaKind.VIDEO -> "Видео"
            MessageMediaKind.VOICE -> "Голосовое сообщение"
            MessageMediaKind.VIDEO_MESSAGE -> "Видеосообщение"
            MessageMediaKind.AUDIO -> "Аудио"
            MessageMediaKind.FILE -> "Файл"
            MessageMediaKind.STICKER -> "Стикер"
            MessageMediaKind.GIF -> "GIF"
            MessageMediaKind.LOCATION -> "Геопозиция"
            MessageMediaKind.CONTACT -> "Контакт"
            MessageMediaKind.POLL -> "Опрос"
            MessageMediaKind.CALL -> "Звонок"
            MessageMediaKind.GROUP_CALL -> "Групповой звонок"
        }

        fun typingText(count: Int, type: ChatType): String =
            if (count <= 1 || type != ChatType.GROUP) "печатает…" else TypingText.counted(count)

        fun unreadPhrase(count: Int): String {
            val tens = count % 100
            val ones = count % 10
            return when {
                tens in 11..14 -> "$count непрочитанных сообщений"
                ones == 1 -> "$count непрочитанное сообщение"
                ones in 2..4 -> "$count непрочитанных сообщения"
                else -> "$count непрочитанных сообщений"
            }
        }

        fun singleLine(text: String): String =
            text.lines().map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" ")
    }

    private fun spoken(item: ChatListItem, chat: Chat): String {
        val parts = mutableListOf(item.title)
        if (item.isVerified) parts += "подтверждённый"
        if (item.isBot) parts += "бот" else if (item.type == ChatType.CHANNEL) parts += "канал"
        if (item.isOnline) parts += "в сети"
        if (item.isPinned) parts += "закреплён"
        if (item.isMuted) parts += "без звука"
        when (item.previewStyle) {
            ChatListItem.PreviewStyle.DRAFT -> parts += "черновик: ${item.preview}"
            ChatListItem.PreviewStyle.TYPING, ChatListItem.PreviewStyle.EMPTY -> parts += item.preview
            ChatListItem.PreviewStyle.MESSAGE -> parts += item.sender?.let { "$it: ${item.preview}" } ?: item.preview
        }
        if (item.time.isNotEmpty()) parts += item.time
        when (item.delivery) {
            DeliveryState.SENDING -> parts += "отправляется"
            DeliveryState.SENT -> parts += "доставлено"
            DeliveryState.READ -> parts += "прочитано"
            DeliveryState.FAILED -> parts += "не отправлено"
            null -> Unit
        }
        if (chat.unreadCount > 0) parts += unreadPhrase(chat.unreadCount) else if (chat.isMarkedUnread) parts += "помечен непрочитанным"
        if (item.hasMention) parts += "есть упоминание"
        if (item.openApp) parts += "открыть приложение"
        return parts.joinToString(", ")
    }
}
