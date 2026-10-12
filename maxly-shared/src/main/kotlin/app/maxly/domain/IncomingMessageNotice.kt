package app.maxly.domain

/**
 * Новое чужое сообщение, только что пришедшее пушем ядра. По нему приложение, пока оно не на
 * экране, показывает уведомление. [media] — подпись вложения, как в списке чатов («Фото»),
 * пустая — вложения нет.
 */
data class IncomingMessageNotice(
    val chatId: String,
    val messageId: String,
    val chatTitle: String,
    val chatType: ChatType,
    val authorName: String,
    val text: String,
    val media: String,
    val isMuted: Boolean,
    val timeMs: Long,
)
