package app.maxly.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.maxly.domain.AuthPhase
import app.maxly.domain.AuthService
import app.maxly.domain.MaxlyError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.max

/** Шаг экрана входа. */
sealed interface AuthStep {
    data object Phone : AuthStep
    data class Code(val length: Int?) : AuthStep
    data class Password(val hint: String?) : AuthStep
    data object Registration : AuthStep
}

/** Всё, что рисует экран входа. */
data class AuthUiState(
    val step: AuthStep = AuthStep.Phone,
    val title: String = "Вход",
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
    val sessionExpired: Boolean = false,
    /**
     * Отказ сервера во входе по токену, когда токен стёрт: текст над формой входа. Временный отказ
     * сюда не попадает — он остаётся баннером над списком чатов.
     */
    val notice: LoginNotice? = null,
    val country: PhoneCountry? = PhoneCountry.russia,
    val countryCode: String = PhoneCountry.russia.code,
    val countryTitle: String = PhoneCountry.russia.name,
    val nationalNumber: String = "",
    val phonePlaceholder: String = PhoneCountry.russia.pattern,
    val phoneHint: String? = null,
    val canRequestCode: Boolean = false,
    val code: String = "",
    val codeCellCount: Int = 6,
    val codePrompt: String = "",
    val needsManualCodeSubmit: Boolean = false,
    val canVerify: Boolean = false,
    /** Когда можно запросить код снова (мс). `null` — таймера нет. */
    val resendAvailableAtMs: Long? = null,
    val password: String = "",
    val passwordPrompt: String = "",
    val canSubmitPassword: Boolean = false,
    val firstName: String = "",
    val lastName: String = "",
    val canRegister: Boolean = false,
) {
    val canGoBack: Boolean get() = step != AuthStep.Phone

    fun resendSecondsLeft(nowMs: Long): Int {
        val at = resendAvailableAtMs ?: return 0
        return max(0, ((at - nowMs + 999) / 1000).toInt())
    }

    fun canResend(nowMs: Long): Boolean = step is AuthStep.Code && !isBusy && resendSecondsLeft(nowMs) == 0

    fun resendTitle(nowMs: Long): String {
        val left = resendSecondsLeft(nowMs)
        if (left <= 0) return "Отправить код ещё раз"
        return "Отправить код ещё раз через ${left / 60}:${"%02d".format(left % 60)}"
    }
}

/**
 * Вход по номеру: телефон с выбором страны, код из SMS, облачный пароль, регистрация.
 * Повтор кода — через 30 секунд; полный код отправляется сам; неверный код стирается.
 */
class AuthViewModel(
    private val auth: AuthService,
    private val resendIntervalMs: Long = DEFAULT_RESEND_INTERVAL_MS,
    private val now: () -> Long = System::currentTimeMillis,
) : ViewModel() {

    private var step: AuthStep = AuthStep.Phone
    private var isBusy = false
    private var error: MaxlyError? = null
    private var sessionExpired = false
    private var notice: LoginNotice? = null
    private var sentTo: String? = null
    private var resendAvailableAt: Long? = null
    private var countryDigits = PhoneCountry.russia.code
    private var nationalDigits = ""
    private var codeText = ""
    private var country: PhoneCountry? = PhoneCountry.russia
    private var password = ""
    private var firstName = ""
    private var lastName = ""
    private var operation: Job? = null
    private var operationId = 0

    private val _state = MutableStateFlow(AuthUiState())
    val state: StateFlow<AuthUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch { auth.phase.collect { apply(it) } }
        publish()
    }

    // MARK: Ввод

    /** Полный номер (`+7 999…`) из вставки или автозаполнения. */
    fun setPhone(value: String) {
        val edited = PhoneNumber.edit(phoneText, value)
        if (edited == phoneText) return
        split(edited)
        error = null
        publish()
    }

    fun setCountryCode(value: String) {
        val digits = value.filter(Char::isAsciiDigit)
        if (digits.length > 4) {
            split(PhoneNumber.formatted("+$digits"))
            error = null
            publish()
            return
        }
        if (digits == countryDigits) return
        countryDigits = digits
        syncCountry()
        nationalDigits = nationalDigits.take(maxNationalDigits)
        error = null
        publish()
    }

    fun setNationalNumber(value: String) {
        if (value.startsWith("+")) {
            // Автозаполнение или вставка номера целиком, с кодом страны.
            split(PhoneNumber.formatted(value))
            error = null
            publish()
            return
        }
        var digits = value.filter(Char::isAsciiDigit)
        val old = formatNational(nationalDigits)
        if (value.length < old.length && digits == nationalDigits && digits.isNotEmpty()) {
            // Стёрли разделитель: убираем цифру перед ним.
            digits = digits.dropLast(1)
        } else if (countryDigits == PhoneCountry.russia.code && digits.length == 11 && (digits.first() == '8' || digits.first() == '7') &&
            !(nationalDigits.length == maxNationalDigits && digits.startsWith(nationalDigits))
        ) {
            // Российский номер целиком: `8 999 …` или `7 999 …`.
            digits = digits.drop(1)
        }
        digits = digits.take(maxNationalDigits)
        if (digits == nationalDigits) return
        nationalDigits = digits
        error = null
        publish()
    }

    fun selectCountry(selected: PhoneCountry) {
        country = selected
        countryDigits = selected.code
        nationalDigits = nationalDigits.take(maxNationalDigits)
        error = null
        publish()
    }

    fun setCode(value: String) {
        val digits = value.filter(Char::isAsciiDigit).take(expectedCodeLength ?: MAX_CODE_LENGTH)
        if (digits == codeText) return
        codeText = digits
        error = null
        publish()
        val expected = expectedCodeLength
        if (expected != null && digits.length == expected && !isBusy) verify()
    }

    fun setPassword(value: String) {
        if (value == password) return
        password = value
        error = null
        publish()
    }

    fun setFirstName(value: String) {
        if (value == firstName) return
        firstName = value
        error = null
        publish()
    }

    fun setLastName(value: String) {
        if (value == lastName) return
        lastName = value
        error = null
        publish()
    }

    // MARK: Действия

    fun requestCode() {
        if (isBusy) return
        val number = normalizedPhone ?: run {
            error = MaxlyError.Rejected(
                if (countryDigits == PhoneCountry.russia.code) "Введите номер в формате +7 900 000-00-00" else "Проверьте код страны и номер",
            )
            publish()
            return
        }
        perform({ auth.requestCode(number) }) { ok ->
            if (ok) {
                sentTo = number
                codeText = ""
                sessionExpired = false
                notice = null
                resendAvailableAt = now() + resendIntervalMs
            }
        }
    }

    fun resendCode() {
        if (!_state.value.canResend(now())) return
        perform({ auth.resendCode() }) { ok ->
            if (ok) {
                codeText = ""
                resendAvailableAt = now() + resendIntervalMs
            }
        }
    }

    fun verify() {
        if (!canVerify) return
        val code = codeText
        perform({ auth.verifyCode(code) }) { ok ->
            if (!ok && error == MaxlyError.codeRenewed) {
                // Сервис уже выслал новый код: таймер повтора начинается заново.
                resendAvailableAt = now() + resendIntervalMs
            }
            // Неверный код стирается, чтобы набрать новый без лишних действий.
            if (!ok && error is MaxlyError.Rejected) codeText = ""
        }
    }

    fun submitPassword() {
        if (!canSubmitPassword) return
        val value = password
        perform({ auth.submitPassword(value) }) { ok ->
            if (!ok && error is MaxlyError.Rejected) password = ""
        }
    }

    fun register() {
        if (step != AuthStep.Registration || isBusy) return
        val first = firstName.trim()
        val last = lastName.trim()
        if (first.isEmpty()) {
            error = MaxlyError.Rejected("Введите имя")
            publish()
            return
        }
        if (first.length > MAX_NAME_LENGTH || last.length > MAX_NAME_LENGTH) {
            error = MaxlyError.Rejected("Имя и фамилия не длиннее $MAX_NAME_LENGTH символов")
            publish()
            return
        }
        perform({ auth.register(first, last) }) {}
    }

    /** Назад к номеру: текущая попытка входа забывается. */
    fun backToPhone() {
        if (step == AuthStep.Phone) return
        operation?.cancel()
        operation = null
        operationId += 1
        isBusy = false
        error = null
        resetSecrets()
        resendAvailableAt = null
        sentTo = null
        step = AuthStep.Phone
        publish()
        viewModelScope.launch { auth.cancelLogin() }
    }

    // MARK: Внутреннее

    internal fun apply(phase: AuthPhase) {
        when (phase) {
            AuthPhase.Restoring -> Unit
            AuthPhase.SignedOut -> if (step != AuthStep.Phone) {
                resetSecrets()
                resendAvailableAt = null
                step = AuthStep.Phone
            }
            is AuthPhase.Expired -> {
                sessionExpired = true
                notice = LoginNotices.of(phase.rejection).takeIf { it.placement == LoginNotice.Placement.LOGIN_FORM }
                resetSecrets()
                resendAvailableAt = null
                step = AuthStep.Phone
            }
            is AuthPhase.CodeSent -> {
                val next = AuthStep.Code(phase.codeLength)
                if (step != next) {
                    step = next
                    codeText = codeText.take(phase.codeLength ?: MAX_CODE_LENGTH)
                }
                if (resendAvailableAt == null) resendAvailableAt = now() + resendIntervalMs
            }
            is AuthPhase.Password -> {
                val next = AuthStep.Password(phase.hint)
                if (step != next) {
                    password = ""
                    step = next
                }
            }
            AuthPhase.Registration -> step = AuthStep.Registration
            is AuthPhase.SignedIn -> {
                sessionExpired = false
                notice = null
                resetSecrets()
            }
        }
        publish()
    }

    private fun resetSecrets() {
        codeText = ""
        password = ""
    }

    private fun perform(body: suspend () -> Unit, done: (Boolean) -> Unit) {
        isBusy = true
        error = null
        publish()
        val id = ++operationId
        operation = viewModelScope.launch {
            val failure: MaxlyError? = try {
                body()
                null
            } catch (e: MaxlyError) {
                e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                MaxlyError.Unknown
            }
            if (id != operationId) return@launch
            operation = null
            isBusy = false
            error = if (failure == MaxlyError.Cancelled) null else failure
            done(failure == null)
            publish()
        }
    }

    private val phoneText: String
        get() {
            if (countryDigits == PhoneCountry.russia.code) {
                return if (nationalDigits.isEmpty()) "" else PhoneNumber.formatted("+7$nationalDigits")
            }
            if (countryDigits.isEmpty() && nationalDigits.isEmpty()) return ""
            return "+$countryDigits$nationalDigits"
        }

    private val maxNationalDigits: Int get() = country?.maxDigits ?: max(0, 15 - countryDigits.length)

    private fun formatNational(digits: String): String = country?.format(digits) ?: digits

    private fun split(formatted: String) {
        val digits = formatted.filter(Char::isAsciiDigit)
        when {
            formatted.isEmpty() -> {
                countryDigits = country?.code ?: PhoneCountry.russia.code
                nationalDigits = ""
            }
            formatted.startsWith("+7") || !formatted.startsWith("+") -> {
                countryDigits = "7"
                nationalDigits = digits.drop(1)
            }
            else -> {
                val code = PhoneCountry.longestCode(digits) ?: digits.take(3)
                countryDigits = code
                nationalDigits = digits.drop(code.length)
            }
        }
        syncCountry()
        nationalDigits = nationalDigits.take(maxNationalDigits)
    }

    private fun syncCountry() {
        if (country?.code == countryDigits) return
        country = PhoneCountry.preferred(countryDigits)
    }

    private val expectedCodeLength: Int? get() = (step as? AuthStep.Code)?.length

    internal val normalizedPhone: String?
        get() {
            if (countryDigits == PhoneCountry.russia.code) return PhoneNumber.normalized("+7$nationalDigits")
            if (countryDigits.isEmpty() || countryDigits.first() == '0') return null
            val c = country
            if (c != null) {
                if (nationalDigits.length !in c.minDigits..c.maxDigits) return null
                return "+$countryDigits$nationalDigits"
            }
            return PhoneNumber.normalized("+$countryDigits$nationalDigits")
        }

    private val phoneHint: String?
        get() {
            if (normalizedPhone != null) return null
            if (countryDigits == PhoneCountry.russia.code) {
                return if (nationalDigits.length >= 10) "Проверьте номер: например, +7 900 000-00-00" else null
            }
            if (country == null && countryDigits.isNotEmpty() && nationalDigits.length >= 6) return "Проверьте код страны"
            return null
        }

    private val canVerify: Boolean
        get() {
            if (isBusy || step !is AuthStep.Code) return false
            val expected = expectedCodeLength
            return if (expected != null) codeText.length == expected else codeText.length >= 4
        }

    private val canSubmitPassword: Boolean get() = step is AuthStep.Password && !isBusy && password.isNotEmpty()

    private fun publish() {
        val number = sentTo?.let(PhoneNumber::display) ?: "ваш номер"
        val length = expectedCodeLength
        val currentStep = step
        val first = firstName.trim()
        _state.value = AuthUiState(
            step = currentStep,
            title = when (currentStep) {
                AuthStep.Phone -> "Вход"
                is AuthStep.Code -> "Код из SMS"
                is AuthStep.Password -> "Пароль"
                AuthStep.Registration -> "Новый аккаунт"
            },
            isBusy = isBusy,
            errorMessage = error?.userMessage,
            sessionExpired = sessionExpired,
            notice = notice,
            country = country,
            countryCode = countryDigits,
            countryTitle = country?.name ?: if (countryDigits.isEmpty()) "Выберите страну" else "Другая страна",
            nationalNumber = formatNational(nationalDigits),
            phonePlaceholder = country?.pattern ?: "000 000 0000",
            phoneHint = phoneHint,
            canRequestCode = !isBusy && normalizedPhone != null,
            code = codeText,
            codeCellCount = length ?: max(6, codeText.length),
            codePrompt = if (length != null) "Мы отправили код из $length цифр на $number" else "Мы отправили код на $number",
            needsManualCodeSubmit = currentStep is AuthStep.Code && currentStep.length == null,
            canVerify = canVerify,
            resendAvailableAtMs = resendAvailableAt,
            password = password,
            passwordPrompt = (currentStep as? AuthStep.Password)?.hint?.takeIf { it.isNotEmpty() }
                ?.let { "Аккаунт защищён облачным паролем. Подсказка: $it" } ?: "Аккаунт защищён облачным паролем",
            canSubmitPassword = canSubmitPassword,
            firstName = firstName,
            lastName = lastName,
            canRegister = currentStep == AuthStep.Registration && !isBusy && first.isNotEmpty() &&
                first.length <= MAX_NAME_LENGTH && lastName.length <= MAX_NAME_LENGTH,
        )
    }

    companion object {
        const val DEFAULT_RESEND_INTERVAL_MS = 30_000L
        const val MAX_CODE_LENGTH = 8
        const val MAX_NAME_LENGTH = 60
    }
}
