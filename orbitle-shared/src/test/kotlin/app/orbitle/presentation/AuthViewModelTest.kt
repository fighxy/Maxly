package app.orbitle.presentation

import app.orbitle.MainDispatcherRule
import app.orbitle.domain.AuthPhase
import app.orbitle.domain.AuthService
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.SessionRejection
import app.orbitle.presentation.auth.AuthStep
import app.orbitle.presentation.auth.AuthViewModel
import app.orbitle.presentation.auth.PhoneCountry
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class FakeAuth : AuthService {
    override val phase = MutableStateFlow<AuthPhase>(AuthPhase.SignedOut)
    override val connection = MutableStateFlow(ConnectionState.ONLINE)
    val requested = mutableListOf<String>()
    val codes = mutableListOf<String>()
    var codeLength: Int? = 6
    var verifyError: OrbitleError? = null
    var passwordError: OrbitleError? = null
    var nextAfterCode: AuthPhase = AuthPhase.SignedIn("1")
    var resends = 0
    var cancels = 0

    override suspend fun restoreSession() = Unit
    override suspend fun requestCode(phone: String) {
        requested += phone
        phase.value = AuthPhase.CodeSent(codeLength)
    }
    override suspend fun resendCode() {
        resends += 1
    }
    override suspend fun verifyCode(code: String) {
        codes += code
        verifyError?.let { throw it }
        phase.value = nextAfterCode
    }
    override suspend fun submitPassword(password: String) {
        passwordError?.let { throw it }
        phase.value = AuthPhase.SignedIn("1")
    }
    override suspend fun register(firstName: String, lastName: String) {
        phase.value = AuthPhase.SignedIn("1")
    }
    override suspend fun cancelLogin() {
        cancels += 1
        phase.value = AuthPhase.SignedOut
    }
    override suspend fun logout() {
        phase.value = AuthPhase.SignedOut
    }
}

class AuthViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private var clock = 1_000_000L
    private val auth = FakeAuth()
    private val vm by lazy { AuthViewModel(auth, now = { clock }) }

    @Test
    fun russianNumberFlow() {
        vm.setNationalNumber("9991234567")
        assertEquals("999 123 4567", vm.state.value.nationalNumber)
        assertTrue(vm.state.value.canRequestCode)
        vm.requestCode()
        assertEquals(listOf("+79991234567"), auth.requested)
        val state = vm.state.value
        assertEquals(AuthStep.Code(6), state.step)
        assertEquals("Код из SMS", state.title)
        assertEquals("Мы отправили код из 6 цифр на +7 999 123-45-67", state.codePrompt)
        assertEquals(30, state.resendSecondsLeft(clock))
        assertEquals("Отправить код ещё раз через 0:30", state.resendTitle(clock))
        assertFalse(state.canResend(clock))
        assertTrue(state.canResend(clock + 30_000))
    }

    @Test
    fun fullRussianNumberWithEightIsTrimmed() {
        vm.setNationalNumber("89991234567")
        assertEquals("999 123 4567", vm.state.value.nationalNumber)
    }

    @Test
    fun pastedInternationalNumberPicksCountry() {
        vm.setNationalNumber("+375291234567")
        assertEquals("375", vm.state.value.countryCode)
        assertEquals("Беларусь", vm.state.value.country?.name)
        assertEquals("29 123 4567", vm.state.value.nationalNumber)
        assertTrue(vm.state.value.canRequestCode)
    }

    @Test
    fun unknownCountryCode() {
        vm.setCountryCode("+999")
        assertNull(vm.state.value.country)
        assertEquals("Другая страна", vm.state.value.countryTitle)
        vm.setCountryCode("")
        assertEquals("Выберите страну", vm.state.value.countryTitle)
    }

    @Test
    fun selectCountryTrimsDigits() {
        vm.setNationalNumber("9991234567")
        vm.selectCountry(PhoneCountry.preferred("373")!!)
        assertEquals("99 912 345", vm.state.value.nationalNumber)
    }

    @Test
    fun invalidNumberShowsHint() {
        vm.requestCode()
        assertEquals("Введите номер в формате +7 900 000-00-00", vm.state.value.errorMessage)
        assertTrue(auth.requested.isEmpty())
    }

    @Test
    fun fullCodeSubmitsItself() {
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        vm.setCode("12345")
        assertTrue(auth.codes.isEmpty())
        vm.setCode("123456")
        assertEquals(listOf("123456"), auth.codes)
    }

    @Test
    fun wrongCodeClearsField() {
        auth.verifyError = OrbitleError.Rejected("Неверный код")
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        vm.setCode("111111")
        assertEquals("", vm.state.value.code)
        assertEquals("Неверный код", vm.state.value.errorMessage)
    }

    @Test
    fun renewedCodeRestartsTimer() {
        auth.verifyError = OrbitleError.codeRenewed
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        clock += 40_000
        vm.setCode("111111")
        assertEquals(30, vm.state.value.resendSecondsLeft(clock))
    }

    @Test
    fun unknownCodeLengthNeedsButton() {
        auth.codeLength = null
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        assertTrue(vm.state.value.needsManualCodeSubmit)
        vm.setCode("123")
        assertFalse(vm.state.value.canVerify)
        vm.setCode("1234")
        assertTrue(vm.state.value.canVerify)
        assertEquals("Мы отправили код на +7 999 123-45-67", vm.state.value.codePrompt)
    }

    @Test
    fun passwordStepWithHint() {
        auth.nextAfterCode = AuthPhase.Password("кот")
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        vm.setCode("123456")
        assertEquals(AuthStep.Password("кот"), vm.state.value.step)
        assertEquals("Аккаунт защищён облачным паролем. Подсказка: кот", vm.state.value.passwordPrompt)
        auth.passwordError = OrbitleError.Rejected("Неверный пароль")
        vm.setPassword("secret")
        vm.submitPassword()
        assertEquals("", vm.state.value.password)
        assertEquals("Неверный пароль", vm.state.value.errorMessage)
    }

    @Test
    fun registrationValidatesName() {
        auth.nextAfterCode = AuthPhase.Registration
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        vm.setCode("123456")
        assertEquals(AuthStep.Registration, vm.state.value.step)
        assertFalse(vm.state.value.canRegister)
        vm.setFirstName("  Иван ")
        assertTrue(vm.state.value.canRegister)
        vm.setFirstName("x".repeat(61))
        assertFalse(vm.state.value.canRegister)
    }

    @Test
    fun backToPhoneCancelsLogin() {
        vm.setNationalNumber("9991234567")
        vm.requestCode()
        vm.backToPhone()
        assertEquals(AuthStep.Phone, vm.state.value.step)
        assertEquals(1, auth.cancels)
        assertEquals("999 123 4567", vm.state.value.nationalNumber)
    }

    @Test
    fun expiredSessionFlag() {
        auth.phase.value = AuthPhase.Expired()
        assertTrue(vm.state.value.sessionExpired)
        assertEquals(AuthStep.Phone, vm.state.value.step)
    }

    @Test
    fun rejectedTokenShowsTheServerTextOverTheLoginForm() {
        val blocked = SessionRejection(SessionRejection.Reason.BLOCKED, title = "Аккаунт заблокирован", localizedMessage = "Обратитесь в поддержку")
        auth.phase.value = AuthPhase.Expired(blocked)
        val notice = vm.state.value.notice!!
        assertEquals("Аккаунт заблокирован", notice.title)
        assertEquals("Обратитесь в поддержку", notice.message)
        assertEquals(app.orbitle.presentation.auth.LoginNotice.Placement.LOGIN_FORM, notice.placement)
        assertEquals(AuthStep.Phone, vm.state.value.step)
        // Новый вход по номеру убирает надпись.
        vm.setPhone("+7 999 123-45-67")
        vm.requestCode()
        assertNull(vm.state.value.notice)
    }

    @Test
    fun floodNeverReachesTheLoginForm() {
        // Временный отказ — баннер списка чатов: даже если он пришёл как Expired, над формой его нет.
        auth.phase.value = AuthPhase.Expired(SessionRejection(SessionRejection.Reason.FLOOD))
        assertNull(vm.state.value.notice)
    }
}
