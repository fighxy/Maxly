package app.orbitle.presentation.chat

import app.orbitle.data.ChatHeaderInfo
import app.orbitle.domain.ChatType
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.common.PresenceText
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Подписи экрана чата: время пузыря, разделители дней, вторая строка шапки. */
class ChatFormatter(private val zone: ZoneId = ZoneId.systemDefault()) {
    private val presence = PresenceText(zone)

    fun time(ms: Long): String {
        val date = Instant.ofEpochMilli(ms).atZone(zone)
        return "%02d:%02d".format(date.hour, date.minute)
    }

    /** Ключ дня для группировки: дата в часовом поясе телефона. */
    fun dayKey(ms: Long): String = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate().toString()

    /** «Сегодня», «Вчера», «5 марта», «5 марта 2025». */
    fun dayLabel(ms: Long, nowMs: Long): String {
        val date = Instant.ofEpochMilli(ms).atZone(zone)
        val now = Instant.ofEpochMilli(nowMs).atZone(zone)
        val days = ChronoUnit.DAYS.between(date.toLocalDate(), now.toLocalDate())
        val month = PresenceText.MONTHS_GENITIVE[date.monthValue - 1]
        return when {
            days == 0L -> "Сегодня"
            days == 1L -> "Вчера"
            date.year == now.year -> "${date.dayOfMonth} $month"
            else -> "${date.dayOfMonth} $month ${date.year}"
        }
    }

    /** Вторая строка шапки и подсвечивать ли её акцентом («в сети», «печатает…»). */
    fun subtitle(info: ChatHeaderInfo, nowMs: Long): Pair<String, Boolean> {
        val chat = info.chat
        if (info.typing.isNotEmpty() && !chat.isSavedMessages) {
            val text = if (chat.type == ChatType.GROUP && info.typing.size == 1) {
                "${info.typing.first()} печатает…"
            } else {
                ChatListFormatter.typingText(info.typing.size, chat.type)
            }
            return text to true
        }
        if (chat.isSavedMessages) return "ваши сообщения и заметки" to false
        if (chat.isBot) return "бот" to false
        return when (chat.type) {
            ChatType.CHANNEL -> {
                val count = info.participants ?: return "канал" to false
                "${PresenceText.grouped(count)} ${PresenceText.plural(count, "подписчик", "подписчика", "подписчиков")}" to false
            }
            ChatType.GROUP -> {
                val count = info.participants ?: return "группа" to false
                "${PresenceText.grouped(count)} ${PresenceText.plural(count, "участник", "участника", "участников")}" to false
            }
            else -> presence.status(chat.isOnline, info.lastSeenMs, nowMs) to chat.isOnline
        }
    }
}
