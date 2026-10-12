package app.maxly.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * «Звонки и сообщения в фоне»: держать ли соединение, пока приложение свёрнуто, и показывать
 * ли уведомления о новых сообщениях. По умолчанию включено, как на iOS.
 */
class NotificationSettings(private val store: PreferenceStore) {
    private val _enabled = MutableStateFlow(store.get(KEY) != "false")
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun setEnabled(value: Boolean) {
        store.put(KEY, value.toString())
        _enabled.value = value
    }

    private companion object {
        const val KEY = "notifications.background"
    }
}
