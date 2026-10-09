package app.maxly.data

import com.maxly.core.api.PresenceInfo
import com.maxly.shared.MaxClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * Режим призрака и отметки о прочтении — два независимых флага ядра. Глушит активность само ядро
 * (пинги и `LOGIN` с `interactive: false`, «печатает», запись, загрузка, стикеры, отметки
 * о прочтении и просмотры историй) и само ведёт локальные отметки прочитанного; клиент только
 * переключает флаги и ничего из этого не повторяет. Оба флага — настройки устройства: выход их
 * не сбрасывает, а выключение ничего не отправляет задним числом.
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
 * Флаги ядра: [MaxClient.ghostMode] и [MaxClient.hideReadReceipts] хранит и применяет ядро,
 * а их смена (отсюда или из другого места) приходит в `MaxState.ghostMode` /
 * `MaxState.hideReadReceipts` стора — оттуда и берутся [ghostMode] и [hideReadReceipts].
 * Отдельного события смены у ядра нет. Включение режима призрака ядро само сводит с флагом
 * активности приложения ([MaxClient.setInteractive]): серверу уходит `interactive: false`.
 *
 * Перенос со старой заглушки: флаги, включённые в её ключах [LEGACY_GHOST] и
 * [LEGACY_READ_RECEIPTS], один раз включаются в ядре (если там они ещё выключены), и ключи
 * удаляются.
 */
class CoreGhostModeRepository(
    private val client: MaxClient,
    scope: CoroutineScope,
    legacy: PreferenceStore? = null,
) : GhostModeRepository {

    init {
        legacy?.let { migrate(it, client) }
    }

    override val ghostMode: StateFlow<Boolean> = client.store.state
        .map { it.ghostMode }
        .distinctUntilChanged()
        .stateIn(scope, SharingStarted.Eagerly, client.ghostMode)

    override val hideReadReceipts: StateFlow<Boolean> = client.store.state
        .map { it.hideReadReceipts }
        .distinctUntilChanged()
        .stateIn(scope, SharingStarted.Eagerly, client.hideReadReceipts)

    /** Сеттер ядра сам шлёт `PING` с новым `interactive`, если тот сменился. */
    override fun setGhostMode(enabled: Boolean) {
        if (client.ghostMode != enabled) client.ghostMode = enabled
    }

    override fun setHideReadReceipts(enabled: Boolean) {
        if (client.hideReadReceipts != enabled) client.hideReadReceipts = enabled
    }

    /** Всегда свежий `CONTACT_PRESENCE` о себе ([MaxClient.checkOwnPresence]); без входа — `null`. */
    override suspend fun checkOwnPresence(): PeerPresence? {
        if (client.store.state.value.me == null && client.userId.value == null) return null
        return MaxCoreGateway.read { client.checkOwnPresence() }?.let(::presenceOf)
    }

    companion object {
        /** Ключи заглушки до флагов ядра: только для переноса. */
        const val LEGACY_GHOST = "ghostMode.enabled"
        const val LEGACY_READ_RECEIPTS = "ghostMode.hideReadReceipts"

        /** Запись присутствия ядра — в нашу: «в сети», время в мс и код статуса. */
        fun presenceOf(info: PresenceInfo): PeerPresence =
            PeerPresence(PresenceTime.isOnline(info), PresenceTime.ms(info.seen), PresenceTime.status(info))

        /**
         * Один раз переносит флаги заглушки в ядро: включённый там флаг включается в ядре, если
         * в ядре он ещё выключен (включённый в ядре не трогается), затем ключ удаляется.
         */
        fun migrate(legacy: PreferenceStore, client: MaxClient) {
            if (takeLegacy(legacy, LEGACY_GHOST) && !client.ghostMode) client.ghostMode = true
            if (takeLegacy(legacy, LEGACY_READ_RECEIPTS) && !client.hideReadReceipts) client.hideReadReceipts = true
        }

        /** Был ли флаг [key] включён; ключ, если он был, удаляется. */
        private fun takeLegacy(legacy: PreferenceStore, key: String): Boolean {
            val value = legacy.get(key)
            if (value.isNullOrEmpty()) return false
            legacy.remove(key)
            return value == "true"
        }
    }
}
