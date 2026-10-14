package app.maxly.platform

import app.maxly.data.PreferenceStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Настройки значка в трее: сворачивать ли окно в трей при закрытии (по умолчанию да) и звучат
 * ли уведомления о сообщениях («Без звука» в меню значка, по умолчанию звук есть).
 */
class DesktopTraySettings(private val store: PreferenceStore) {
    private val _closeToTray = MutableStateFlow(store.get(CLOSE_KEY) != "false")
    val closeToTray: StateFlow<Boolean> = _closeToTray.asStateFlow()

    private val _muted = MutableStateFlow(store.get(MUTE_KEY) == "true")
    val muted: StateFlow<Boolean> = _muted.asStateFlow()

    fun setCloseToTray(value: Boolean) {
        store.put(CLOSE_KEY, value.toString())
        _closeToTray.value = value
    }

    fun setMuted(value: Boolean) {
        store.put(MUTE_KEY, value.toString())
        _muted.value = value
    }

    private companion object {
        const val CLOSE_KEY = "tray.closeToTray"
        const val MUTE_KEY = "tray.muted"
    }
}
