package app.maxly.presentation.chat

import app.maxly.domain.ChatType

/** Одно закреплённое сообщение в плашке над лентой. */
data class PinnedEntry(val messageId: String, val preview: String)

/**
 * Плашка закрепов: сообщения от нового к старому и то, что показано сейчас.
 * Касание открывает показанное и переходит к следующему, после последнего — снова к первому.
 */
data class PinnedBar(val entries: List<PinnedEntry> = emptyList(), val index: Int = 0) {
    val current: PinnedEntry? get() = entries.getOrNull(index)
    val count: Int get() = entries.size

    /** Заголовок плашки: «Закреплённое сообщение» или «… 2 из 3». */
    val title: String
        get() = if (count > 1) "Закреплённое сообщение ${index + 1} из $count" else "Закреплённое сообщение"

    fun next(): PinnedBar = if (count <= 1) this else copy(index = (index + 1) % count)

    /** Новый список с сервера: показанное остаётся, если его не открепили, иначе первое. */
    fun replace(next: List<PinnedEntry>): PinnedBar {
        val keep = current?.messageId?.let { id -> next.indexOfFirst { it.messageId == id } } ?: -1
        return PinnedBar(next, if (keep >= 0) keep else 0)
    }

    fun without(messageId: String): PinnedBar = replace(entries.filterNot { it.messageId == messageId })

    operator fun contains(messageId: String): Boolean = entries.any { it.messageId == messageId }
}

/** Вариант закрепа в меню сообщения. */
data class PinChoice(val label: String, val forMe: Boolean, val notify: Boolean)

object PinChoices {
    /**
     * Где что имеет смысл: в личном чате — «только у меня» (собеседник закреп не видит),
     * в группе и канале — без уведомления участникам. В «Избранном» выбора нет.
     */
    fun of(type: ChatType, savedMessages: Boolean): List<PinChoice> = when {
        savedMessages -> listOf(PinChoice("Закрепить", forMe = false, notify = true))
        type == ChatType.PRIVATE -> listOf(
            PinChoice("Закрепить у всех", forMe = false, notify = true),
            PinChoice("Закрепить только у меня", forMe = true, notify = true),
        )
        else -> listOf(
            PinChoice("Закрепить и уведомить", forMe = false, notify = true),
            PinChoice("Закрепить без уведомления", forMe = false, notify = false),
        )
    }
}

/**
 * Пуш «вложение не обработано» (`NOTIF_ATTACH` с `error`). Если в нём есть id вложения, ядро само
 * обрывает загрузку с этим id ошибкой сервера, и клиенту трогать ничего не нужно. Без id пуш
 * относится к загрузке, только когда она одна; при нескольких непонятно к какой, и ни одна не трогается.
 */
object AttachmentFailures {
    fun target(inFlight: Collection<String>, uploadId: Long? = null): String? =
        if (uploadId != null) null else inFlight.singleOrNull()

    /**
     * Текст для экрана, как на iOS: «Вложение не отправлено: <ошибка сервера>». Причина нужна:
     * сервер может не принять файл по типу или размеру, и повтор тогда не поможет.
     */
    fun text(server: String?): String =
        server?.trim()?.takeIf { it.isNotEmpty() }?.let { "$NOT_SENT: $it" } ?: NOT_SENT

    private const val NOT_SENT = "Вложение не отправлено"
}
