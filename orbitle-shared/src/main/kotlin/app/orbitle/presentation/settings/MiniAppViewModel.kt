package app.orbitle.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.AccountRepository
import app.orbitle.data.CoreErrors
import app.orbitle.domain.MiniApp
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Лист мини-приложения: запуск и перезапуск после внешнего шага.
 * Каждое открытие — новый экземпляр и новый запуск.
 */
class MiniAppViewModel(
    /** Приложение настроек; `null` у приложения бота. */
    val kind: MiniApp.Kind?,
    private val repository: AccountRepository,
    /** Заголовок приложения бота. */
    private val botTitle: String? = null,
    /** Запуск приложения бота (кнопка «Открыть приложение», inline-кнопка `OPEN_APP`). */
    private val start: (suspend () -> MiniApp)? = null,
) : ViewModel() {

    sealed interface Phase {
        data object Loading : Phase
        data class Ready(val app: MiniApp) : Phase
        data class Failed(val message: String) : Phase
    }

    data class State(
        val phase: Phase = Phase.Loading,
        val showsBackButton: Boolean = false,
        val closingNeedsConfirmation: Boolean = false,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    val title: String get() = botTitle ?: kind?.title ?: "Приложение"

    private var ticket = 0

    fun launch() = work {
        start?.invoke() ?: repository.launchMiniApp(kind ?: throw OrbitleError.InvalidRequest)
    }

    /** Возврат с внешнего шага: сервер даёт новый запуск, лист открывает его. */
    fun handleCallback(url: String) = work { repository.miniAppCallback(url) }

    fun showBackButton(visible: Boolean) {
        _state.update { it.copy(showsBackButton = visible) }
    }

    fun setClosingConfirmation(needed: Boolean) {
        _state.update { it.copy(closingNeedsConfirmation = needed) }
    }

    private fun work(block: suspend () -> MiniApp) {
        val current = ++ticket
        _state.update { it.copy(phase = Phase.Loading) }
        viewModelScope.launch {
            try {
                val app = block()
                if (current == ticket) _state.update { it.copy(phase = Phase.Ready(app)) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (current == ticket) _state.update { it.copy(phase = Phase.Failed(message(e))) }
            }
        }
    }

    private fun message(error: Throwable): String =
        CoreErrors.map(error).userMessage ?: CoreErrors.UNKNOWN_TEXT
}
