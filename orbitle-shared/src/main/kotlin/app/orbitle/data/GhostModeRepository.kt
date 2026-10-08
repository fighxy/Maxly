package app.orbitle.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Режим призрака и отметки о прочтении — два независимых флага ядра. Глушит активность само ядро
 * (пинги, `setInteractive` / `setAppActive`, «печатает», запись, загрузка, стикеры, отметки
 * о прочтении) и само ведёт локальные отметки прочитанного; клиент только переключает флаги
 * и ничего из этого не повторяет. Оба флага — настройки устройства: выход их не сбрасывает,
 * а выключение ничего не отправляет задним числом.
 */
interface GhostModeRepository {
    /** Не показывать, что я в сети, и не сообщать «печатает…», запись, загрузку и стикеры. */
    val ghostMode: StateFlow<Boolean>

    fun setGhostMode(enabled: Boolean)

    /** Не отправлять отметки о прочтении. */
    val hideReadReceipts: StateFlow<Boolean>

    fun setHideReadReceipts(enabled: Boolean)

    /**
     * Свой статус так, как его видит сервер: один запрос, без повторов. `null` — сервер
     * не ответил или спросить пока нечем.
     */
    suspend fun checkOwnPresence(): PeerPresence?
}

/**
 * Заглушка до API ядра: флаги лежат в локальных настройках и никуда не уходят, свой статус
 * неизвестен. Когда ядро даст `setGhostMode` / `ghostMode()`, `setHideReadReceipts` /
 * `hideReadReceipts()` и `checkOwnPresence()`, её заменит реализация над ним.
 */
class LocalGhostModeRepository(private val store: PreferenceStore) : GhostModeRepository {
    private val _ghostMode = MutableStateFlow(store.get(KEY_GHOST) == "true")
    override val ghostMode: StateFlow<Boolean> = _ghostMode.asStateFlow()

    private val _hideReadReceipts = MutableStateFlow(store.get(KEY_READ_RECEIPTS) == "true")
    override val hideReadReceipts: StateFlow<Boolean> = _hideReadReceipts.asStateFlow()

    override fun setGhostMode(enabled: Boolean) = save(_ghostMode, KEY_GHOST, enabled)

    override fun setHideReadReceipts(enabled: Boolean) = save(_hideReadReceipts, KEY_READ_RECEIPTS, enabled)

    override suspend fun checkOwnPresence(): PeerPresence? = null

    private fun save(flag: MutableStateFlow<Boolean>, key: String, value: Boolean) {
        if (flag.value == value) return
        flag.value = value
        store.put(key, value.toString())
    }

    companion object {
        const val KEY_GHOST = "ghostMode.enabled"
        const val KEY_READ_RECEIPTS = "ghostMode.hideReadReceipts"
    }
}
