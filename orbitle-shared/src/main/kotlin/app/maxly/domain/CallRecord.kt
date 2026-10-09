package app.maxly.domain

/** Звонок из истории вкладки «Звонки». */
data class CallRecord(
    val id: String,
    /** Собеседник: id пользователя или группового чата. */
    val peerId: String,
    val title: String,
    val avatarUrl: String? = null,
    val isGroup: Boolean = false,
    /** Чат, который открывается по нажатию на звонок. */
    val chatId: String? = null,
    val outgoing: Boolean,
    val outcome: CallOutcome,
    val isVideo: Boolean = false,
    val timeMs: Long,
    val durationMs: Long = 0,
) {
    val isMissed: Boolean get() = !outgoing && outcome == CallOutcome.MISSED
}
