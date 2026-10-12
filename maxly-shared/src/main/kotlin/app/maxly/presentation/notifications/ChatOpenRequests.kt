package app.maxly.presentation.notifications

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Чат, который надо открыть по нажатию на уведомление. Запрос ждёт, пока главный экран его
 * заберёт: после холодного запуска экран появляется позже, чем пришло нажатие.
 */
class ChatOpenRequests {
    private val _pending = MutableStateFlow<String?>(null)
    val pending: StateFlow<String?> = _pending.asStateFlow()

    fun request(chatId: String) {
        _pending.value = chatId
    }

    /** Экран открыл чат [chatId]: запрос выполнен. Новый запрос, пришедший тем временем, остаётся. */
    fun consume(chatId: String) {
        _pending.compareAndSet(chatId, null)
    }
}
