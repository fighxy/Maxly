package app.orbitle.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.AccountRepository
import app.orbitle.data.CoreErrors
import app.orbitle.domain.TwoFactorStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * «Безопасность»: статус облачного пароля, его включение, смена и выключение,
 * и почта восстановления. Семейная защита отдельным запросом не пишется.
 */
class SecurityViewModel(private val repository: AccountRepository) : ViewModel() {

    enum class PasswordForm { NONE, ENABLE, CHANGE, DISABLE }

    data class State(
        /** `true`, пока первый ответ ещё не пришёл. */
        val loading: Boolean = true,
        val status: TwoFactorStatus? = null,
        /** Текст, если статус не загрузился. Почта при этом не показывается. */
        val failure: String? = null,
        val form: PasswordForm = PasswordForm.NONE,
        val working: Boolean = false,
        val formError: String? = null,
        val notice: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Скрытая почта или `null`, если её нет либо статус ещё не известен. */
    val maskedEmail: String?
        get() = _state.value.status?.email?.let(TwoFactorStatus::mask)

    fun load() {
        viewModelScope.launch {
            try {
                val status = repository.twoFactorStatus()
                _state.update { it.copy(loading = false, status = status, failure = null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(loading = false, status = null, failure = message(e)) }
            }
        }
    }

    /** Статус сразу после смены почты, без повторного запроса. */
    fun apply(status: TwoFactorStatus) {
        _state.update { it.copy(loading = false, status = status, failure = null) }
    }

    fun openForm(form: PasswordForm) {
        _state.update { it.copy(form = form, formError = null, notice = null) }
    }

    fun closeForm() {
        _state.update { it.copy(form = PasswordForm.NONE, formError = null, working = false) }
    }

    fun enablePassword(password: String, hint: String) {
        if (password.isEmpty() || _state.value.working) {
            if (password.isEmpty()) _state.update { it.copy(formError = "Введите пароль") }
            return
        }
        work("Пароль включён") { repository.enablePassword(password, hint) }
    }

    fun changePassword(oldPassword: String, newPassword: String) {
        when {
            _state.value.working -> return
            oldPassword.isEmpty() || newPassword.isEmpty() -> _state.update { it.copy(formError = "Введите оба пароля") }
            oldPassword == newPassword -> _state.update { it.copy(formError = "Новый пароль совпадает со старым") }
            else -> work("Пароль изменён") { repository.changePassword(oldPassword, newPassword) }
        }
    }

    fun disablePassword(password: String) {
        if (password.isEmpty() || _state.value.working) {
            if (password.isEmpty()) _state.update { it.copy(formError = "Введите пароль") }
            return
        }
        work("Пароль выключен") { repository.disablePassword(password) }
    }

    private fun work(notice: String, block: suspend () -> Unit) {
        _state.update { it.copy(working = true, formError = null, notice = null) }
        viewModelScope.launch {
            try {
                block()
                val status = runCatching { repository.twoFactorStatus() }.getOrNull()
                _state.update {
                    it.copy(
                        working = false,
                        form = PasswordForm.NONE,
                        notice = notice,
                        status = status ?: it.status,
                        loading = false,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(working = false, formError = CoreErrors.text(e, "Не удалось изменить пароль")) }
            }
        }
    }

    private fun message(e: Throwable): String = CoreErrors.map(e).userMessage ?: CoreErrors.UNKNOWN_TEXT
}

/**
 * Смена почты для восстановления: пароль → почта → код из письма.
 * [now] — текущее время в миллисекундах, в тестах подменяется.
 */
class RecoveryEmailViewModel(
    private val repository: AccountRepository,
    private val now: () -> Long = { System.currentTimeMillis() },
) : ViewModel() {

    sealed interface Step {
        data object Password : Step
        data object Email : Step
        data class Code(val email: String) : Step
        data class Done(val status: TwoFactorStatus) : Step
    }

    data class State(
        val step: Step = Step.Password,
        val working: Boolean = false,
        val error: String? = null,
        /** Момент, когда можно выслать код ещё раз, в миллисекундах. */
        val resendAvailableAt: Long? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()
    private var trackId: String? = null

    fun canResend(at: Long = now()): Boolean {
        val until = _state.value.resendAvailableAt ?: return true
        return at >= until
    }

    /** Секунды до повторной отправки, округление вверх. Ноль — можно отправлять. */
    fun resendWaitSeconds(at: Long = now()): Int {
        val until = _state.value.resendAvailableAt ?: return 0
        val left = until - at
        if (left <= 0L) return 0
        return ((left + 999L) / 1000L).toInt()
    }

    fun submitPassword(password: String) {
        if (password.isEmpty() || _state.value.working) return
        work {
            trackId = repository.startEmailChange(password)
            _state.update { it.copy(step = Step.Email) }
        }
    }

    fun submitEmail(email: String) {
        val address = email.trim()
        if (!looksLikeEmail(address)) {
            _state.update { it.copy(error = "Проверьте адрес почты") }
            return
        }
        val track = trackId ?: return
        if (_state.value.working) return
        work {
            val wait = repository.sendEmailCode(track, address)
            _state.update {
                it.copy(step = Step.Code(address), resendAvailableAt = now() + maxOf(wait, 0) * 1000L)
            }
        }
    }

    fun resendCode() {
        val step = _state.value.step as? Step.Code ?: return
        if (!canResend() || _state.value.working) return
        val track = trackId ?: return
        work {
            val wait = repository.sendEmailCode(track, step.email)
            _state.update { it.copy(resendAvailableAt = now() + maxOf(wait, 0) * 1000L) }
        }
    }

    fun submitCode(code: String) {
        val digits = code.filter { it.isDigit() }
        val track = trackId
        if (digits.isEmpty() || track == null || _state.value.working) return
        work {
            val status = repository.confirmEmail(track, digits)
            _state.update { it.copy(step = Step.Done(status)) }
        }
    }

    /** Вернуться к вводу почты с шага кода. */
    fun editEmail() {
        if (_state.value.step is Step.Code) _state.update { it.copy(step = Step.Email, error = null) }
    }

    private fun work(block: suspend () -> Unit) {
        if (_state.value.working) return
        _state.update { it.copy(working = true, error = null) }
        viewModelScope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(error = CoreErrors.text(e)) }
            } finally {
                _state.update { it.copy(working = false) }
            }
        }
    }

    companion object {
        /** Адрес с одним `@`, непустым именем и доменом, в котором есть точка не по краям. */
        fun looksLikeEmail(value: String): Boolean {
            if (' ' in value) return false
            val parts = value.split('@')
            if (parts.size != 2 || parts[0].isEmpty()) return false
            val domain = parts[1]
            return '.' in domain && !domain.startsWith('.') && !domain.endsWith('.')
        }
    }
}
