package app.maxly.domain

/** Сообщение, найденное поиском: на сервере или среди загруженных на устройство. */
data class FoundMessage(
    val chatId: String,
    val messageId: String,
    /** Имя автора, если оно известно. */
    val senderName: String?,
    val isOutgoing: Boolean,
    val text: String,
    /** Мс Unix; 0 — сервер не прислал время. */
    val timeMs: Long,
)
