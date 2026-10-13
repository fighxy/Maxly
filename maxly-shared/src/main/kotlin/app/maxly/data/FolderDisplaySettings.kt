package app.maxly.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Вид полосы папок на этом устройстве: вкладку «Все» можно скрыть. Сервер такого не хранит,
 * поэтому настройка своя у каждого устройства. Без своих папок «Все» видна всё равно.
 */
class FolderDisplaySettings(private val store: PreferenceStore) {
    private val _hidesAllChats = MutableStateFlow(store.get(KEY_HIDE_ALL) == "true")
    val hidesAllChats: StateFlow<Boolean> = _hidesAllChats.asStateFlow()

    fun setHidesAllChats(hide: Boolean) {
        if (_hidesAllChats.value == hide) return
        _hidesAllChats.value = hide
        store.put(KEY_HIDE_ALL, hide.toString())
    }

    companion object {
        const val KEY_HIDE_ALL = "folders.hideAllChats"
    }
}
