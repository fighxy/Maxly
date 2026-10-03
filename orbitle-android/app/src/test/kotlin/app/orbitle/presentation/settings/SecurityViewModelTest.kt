package app.orbitle.presentation.settings

import app.orbitle.MainDispatcherRule
import app.orbitle.data.AccountRepository
import app.orbitle.data.CoreFailure
import app.orbitle.data.TwoFactorErrors
import app.orbitle.domain.Account
import app.orbitle.domain.AccountSettings
import app.orbitle.domain.BlockedUser
import app.orbitle.domain.MiniApp
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.PrivacyChange
import app.orbitle.domain.TwoFactorStatus
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SecurityViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun `recovery email is masked and a blank address is absent`() {
        assertEquals("i•••n@ya.ru", TwoFactorStatus.mask("ivan@ya.ru"))
        assertEquals("a•••@ya.ru", TwoFactorStatus.mask("ab@ya.ru"))
        assertEquals("a•••@b@c.ru", TwoFactorStatus.mask("a@b@c.ru"))
        assertEquals("broken", TwoFactorStatus.mask("broken"))
        assertEquals("@ya.ru", TwoFactorStatus.mask("@ya.ru"))
        assertNull(TwoFactorStatus.of(isEnabled = true, email = "").email)
    }

    @Test
    fun `email address needs a name and a dotted domain`() {
        assertTrue(RecoveryEmailViewModel.looksLikeEmail("ivan@ya.ru"))
        assertFalse(RecoveryEmailViewModel.looksLikeEmail("не почта"))
        assertFalse(RecoveryEmailViewModel.looksLikeEmail("a@b"))
        assertFalse(RecoveryEmailViewModel.looksLikeEmail("a@.ru"))
        assertFalse(RecoveryEmailViewModel.looksLikeEmail("a@b."))
        assertFalse(RecoveryEmailViewModel.looksLikeEmail("a@b c.ru"))
        assertFalse(RecoveryEmailViewModel.looksLikeEmail("a@@b.ru"))
    }

    @Test
    fun `password and code rejections keep the server text`() {
        assertEquals("Неверный пароль", TwoFactorErrors.password(CoreFailure("AUTH", "error.password")).userMessage)
        assertEquals(
            TwoFactorErrors.password(CoreFailure("SERVER", "password.limit")).userMessage,
            "Слишком много попыток. Подождите немного и попробуйте снова",
        )
        assertEquals("Неверный код", TwoFactorErrors.rejection(CoreFailure("SERVER", "email.wrong"), "Неверный код").userMessage)
        assertEquals(
            "Слишком много попыток. Подождите немного и попробуйте снова",
            TwoFactorErrors.rejection(CoreFailure("AUTH", "try.limit"), "Неверный код").userMessage,
        )
        assertEquals("Нет соединения с сервером", TwoFactorErrors.rejection(CoreFailure("NETWORK", null), "Неверный код").userMessage)
    }

    @Test
    fun `email change goes password, address, code`() {
        val repo = EmailAccount()
        val flow = RecoveryEmailViewModel(repo, now = { 0L })
        flow.submitPassword("")
        assertTrue(flow.state.value.step is RecoveryEmailViewModel.Step.Password)
        flow.submitPassword("wrong")
        assertEquals("Неверный пароль", flow.state.value.error)
        assertTrue(flow.state.value.step is RecoveryEmailViewModel.Step.Password)
        flow.submitPassword("secret")
        assertTrue(flow.state.value.step is RecoveryEmailViewModel.Step.Email)
        flow.submitEmail("не почта")
        assertEquals("Проверьте адрес почты", flow.state.value.error)
        flow.submitEmail(" ivan@ya.ru ")
        val code = flow.state.value.step as RecoveryEmailViewModel.Step.Code
        assertEquals("ivan@ya.ru", code.email)
        assertEquals(listOf("track" to "ivan@ya.ru"), repo.emailCodes)
        assertFalse(flow.canResend(0L))
        assertEquals(60, flow.resendWaitSeconds(0L))
        assertTrue(flow.canResend(60_000L))
        flow.submitCode("12-34-56")
        assertEquals("123456", repo.confirmedCode)
        val done = flow.state.value.step as RecoveryEmailViewModel.Step.Done
        assertEquals(TwoFactorStatus.of(true, "ivan@ya.ru"), done.status)
        assertFalse(flow.state.value.working)
    }

    @Test
    fun `loaded password status replaces a failure`() {
        val repo = EmailAccount()
        val model = SecurityViewModel(repo)
        model.load()
        assertEquals(true, model.state.value.status?.isEnabled)
        assertEquals("i•••n@ya.ru", model.maskedEmail)
        repo.failure = OrbitleError.NetworkUnavailable
        model.load()
        assertNull(model.state.value.status)
        assertEquals("Нет соединения с сервером", model.state.value.failure)
        model.apply(TwoFactorStatus.of(true, "a@b.ru"))
        assertEquals("a•••@b.ru", model.maskedEmail)
        assertNull(model.state.value.failure)
    }
}

/** Аккаунт только для смены почты: остальное не используется. */
private class EmailAccount : AccountRepository {
    override val account = MutableStateFlow<Account?>(null)
    override val settings = MutableStateFlow(AccountSettings())
    var failure: OrbitleError? = null
    val emailCodes = mutableListOf<Pair<String, String>>()
    var confirmedCode: String? = null

    override suspend fun reload() = Unit
    override suspend fun updateProfile(firstName: String, lastName: String, about: String) = Unit
    override suspend fun uploadAvatar(jpeg: ByteArray) = Unit
    override suspend fun removeAvatar() = Unit
    override suspend fun requestDeletion(): Long? = null
    override suspend fun change(change: PrivacyChange): AccountSettings = settings.value
    override suspend fun blockedUsers(): List<BlockedUser> = emptyList()
    override suspend fun unblock(userId: String) = Unit

    override suspend fun twoFactorStatus(): TwoFactorStatus {
        failure?.let { throw it }
        return TwoFactorStatus.of(true, "ivan@ya.ru")
    }

    override suspend fun startEmailChange(password: String): String {
        if (password != "secret") throw OrbitleError.Rejected("Неверный пароль")
        return "track"
    }

    override suspend fun sendEmailCode(trackId: String, email: String): Int {
        emailCodes += trackId to email
        return 60
    }

    override suspend fun confirmEmail(trackId: String, code: String): TwoFactorStatus {
        confirmedCode = code
        return TwoFactorStatus.of(true, "ivan@ya.ru")
    }

    override suspend fun launchMiniApp(kind: MiniApp.Kind): MiniApp = MiniApp(1, "https://max.ru")
    override suspend fun miniAppCallback(url: String): MiniApp = MiniApp(1, "https://max.ru")
}
