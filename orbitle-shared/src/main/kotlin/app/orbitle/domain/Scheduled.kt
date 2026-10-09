package app.orbitle.domain

/**
 * Отложенное сообщение чата. [sendAt] — когда уйдёт (`delayedAttributes.timeToFire`, мс), `null` —
 * сервер время не прислал. [failed] — сервер не смог его отправить (`DELAYED_FIRE_ERROR`).
 */
data class ScheduledMessage(val id: String, val text: String, val sendAt: Long?, val failed: Boolean = false)

/** Что сообщил пуш отложенных (`NOTIF_MSG_DELAYED` 154). */
sealed interface ScheduledChange {
    /** Создано или изменено. */
    data class Upsert(val message: ScheduledMessage) : ScheduledChange

    /** Удалено ([fired] `false`) или уже отправлено ([fired] `true`). */
    data class Removed(val ids: List<String>, val fired: Boolean) : ScheduledChange

    /** Тип не узнан или сообщения в пуше нет: список перечитывается. */
    data object Reload : ScheduledChange
}

/** Счётчики опроса из ответа на голос (`SEND_VOTE` 304): всего и по id ответа. */
data class PollTally(val total: Int, val votes: Map<String, Int>)
