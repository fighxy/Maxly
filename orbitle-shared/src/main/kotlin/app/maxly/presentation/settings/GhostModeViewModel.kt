package app.maxly.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.data.GhostModeRepository
import app.maxly.data.OwnPresenceSettings
import app.maxly.data.PeerPresence
import app.maxly.presentation.common.PresenceText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Блок «Дополнительно» в «Конфиденциальности»: режим призрака, «Не отправлять отметки
 * о прочтении», «Показывать мой онлайн» — и строка своего статуса под номером в своём профиле.
 * Ничего не глушит само: это делает ядро по флагам [GhostModeRepository].
 *
 * Свой статус спрашивается раз в [pollMs], пока профиль виден ([setProfileVisible]) и приложение
 * на переднем плане ([foreground]); в фоне опрос стоит. Возврат, смена режима призрака и
 * [refreshOwnPresence] спрашивают сразу и начинают отсчёт заново.
 *
 * @param foreground приложение на переднем плане (десктоп — окно не свёрнуто). Android передаёт
 *   это через [setProfileVisible] по жизненному циклу экрана, ему хватает значения по умолчанию.
 * @param mergeReadReceipts один переключатель вместо двух: режим призрака заодно прячет отметки
 *   о прочтении, отдельного пункта для них нет.
 * @param now текущее время в миллисекундах, в тестах подменяется.
 */
class GhostModeViewModel(
    private val repository: GhostModeRepository,
    private val ownPresence: OwnPresenceSettings,
    foreground: Flow<Boolean> = flowOf(true),
    private val mergeReadReceipts: Boolean = false,
    private val pollMs: Long = POLL_MS,
    private val now: () -> Long = System::currentTimeMillis,
    private val presence: PresenceText = PresenceText(),
) : ViewModel() {

    enum class Toggle { GHOST, READ_RECEIPTS, OWN_PRESENCE }

    data class State(
        val ghostMode: Boolean = false,
        val hideReadReceipts: Boolean = false,
        val showOwnPresence: Boolean = true,
        /** Отметки о прочтении входят в режим призрака: пункта [Toggle.READ_RECEIPTS] нет. */
        val readReceiptsMerged: Boolean = false,
        /** Свой статус с сервера; `null` — неизвестен. */
        val own: PeerPresence? = null,
        /** Подпись [own]: «в сети», «был(а) в 14:05», «не в сети». */
        val ownText: String? = null,
        val checking: Boolean = false,
    ) {
        /** Пункты блока по порядку. */
        val toggles: List<Toggle>
            get() = if (readReceiptsMerged) listOf(Toggle.GHOST, Toggle.OWN_PRESENCE) else Toggle.entries

        /** Строка под номером; `null` — переключатель выключен или статус неизвестен: строки нет. */
        val ownLine: String?
            get() = if (showOwnPresence) ownText else null

        fun isOn(toggle: Toggle): Boolean = when (toggle) {
            Toggle.GHOST -> if (readReceiptsMerged) ghostMode && hideReadReceipts else ghostMode
            Toggle.READ_RECEIPTS -> hideReadReceipts
            Toggle.OWN_PRESENCE -> showOwnPresence
        }

        fun title(toggle: Toggle): String = when (toggle) {
            Toggle.GHOST -> "Режим призрака"
            Toggle.READ_RECEIPTS -> "Не отправлять отметки о прочтении"
            Toggle.OWN_PRESENCE -> "Показывать мой онлайн"
        }

        fun subtitle(toggle: Toggle): String = when (toggle) {
            Toggle.GHOST ->
                if (readReceiptsMerged) "Не показывать, что я в сети, печатаю и читаю"
                else "Не показывать, что я в сети, печатаю, записываю или отправляю файлы"
            Toggle.READ_RECEIPTS -> "Прочитанное отмечается только на этом устройстве"
            Toggle.OWN_PRESENCE -> "Мой статус под номером в профиле — как его видит сервер"
        }
    }

    private val _state = MutableStateFlow(
        State(
            ghostMode = repository.ghostMode.value,
            hideReadReceipts = repository.hideReadReceipts.value,
            showOwnPresence = ownPresence.shown.value,
            readReceiptsMerged = mergeReadReceipts,
        ),
    )
    val state: StateFlow<State> = _state.asStateFlow()

    private val visible = MutableStateFlow(false)
    private val refreshes = MutableStateFlow(0)

    init {
        // Флаги могут смениться и событием ядра, не только отсюда.
        viewModelScope.launch {
            repository.ghostMode.collect { on -> _state.update { it.copy(ghostMode = on) } }
        }
        viewModelScope.launch {
            repository.hideReadReceipts.collect { on -> _state.update { it.copy(hideReadReceipts = on) } }
        }
        viewModelScope.launch {
            ownPresence.shown.collect { shown ->
                _state.update { if (shown) it.copy(showOwnPresence = true) else it.copy(showOwnPresence = false, own = null, ownText = null) }
            }
        }
        // Любая смена входа перезапускает опрос: смена режима призрака и «Обновить» спрашивают сразу.
        viewModelScope.launch {
            combine(visible, foreground, ownPresence.shown, repository.ghostMode, refreshes) { shown, front, enabled, _, _ ->
                shown && front && enabled
            }.collectLatest { active -> if (active) poll() }
        }
    }

    fun set(toggle: Toggle, on: Boolean) {
        when (toggle) {
            Toggle.GHOST -> {
                repository.setGhostMode(on)
                if (mergeReadReceipts) repository.setHideReadReceipts(on)
            }
            Toggle.READ_RECEIPTS -> repository.setHideReadReceipts(on)
            Toggle.OWN_PRESENCE -> ownPresence.setShown(on)
        }
    }

    /** Свой профиль на экране (и экран не остановлен) или ушёл с него. */
    fun setProfileVisible(shown: Boolean) {
        visible.value = shown
    }

    /** Спросить сразу и начать отсчёт заново. Вне профиля или в фоне ничего не делает. */
    fun refreshOwnPresence() {
        refreshes.update { it + 1 }
    }

    private suspend fun poll() {
        while (true) {
            check()
            delay(pollMs)
        }
    }

    private suspend fun check() {
        _state.update { it.copy(checking = true) }
        try {
            val own = try {
                repository.checkOwnPresence()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Сбой — статус неизвестен, строки нет; следующий опрос спросит снова.
                null
            }
            _state.update { if (it.showOwnPresence) it.copy(own = own, ownText = label(own)) else it }
        } finally {
            _state.update { it.copy(checking = false) }
        }
    }

    private fun label(own: PeerPresence?): String? =
        own?.let { presence.status(it.isOnline, it.lastSeenMs, now(), it.presence) ?: OFFLINE }

    companion object {
        /**
         * Пауза между запросами своего статуса: раз в минуту, чтобы не нагружать сервер. Возврат
         * на экран, смена режима призрака и «Обновить» спрашивают сразу.
         */
        const val POLL_MS = 60_000L

        /** Статус есть, но без времени и без «недавно» / «давно». */
        const val OFFLINE = "не в сети"
    }
}
