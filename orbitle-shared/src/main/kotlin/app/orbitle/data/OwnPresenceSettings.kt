package app.orbitle.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * «Показывать мой онлайн»: свой статус под номером в профиле. Включён, пока его не выключили.
 * Только на этом устройстве, ядру и серверу не уходит; выход из аккаунта его не сбрасывает.
 */
class OwnPresenceSettings(private val store: PreferenceStore) {
    private val _shown = MutableStateFlow(store.get(KEY_SHOWN) != "false")
    val shown: StateFlow<Boolean> = _shown.asStateFlow()

    fun setShown(shown: Boolean) {
        if (_shown.value == shown) return
        _shown.value = shown
        store.put(KEY_SHOWN, shown.toString())
    }

    companion object {
        const val KEY_SHOWN = "ghostMode.showOwnPresence"
    }
}
