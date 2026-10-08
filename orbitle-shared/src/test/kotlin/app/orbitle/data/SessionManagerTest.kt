package app.orbitle.data

import app.orbitle.domain.AccountLimits
import app.orbitle.domain.AuthPhase
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.OrbitleError
import app.orbitle.domain.SessionRejection
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class FakeCore : CoreGateway {
    override val phases = MutableSharedFlow<CorePhase>(extraBufferCapacity = 8)
    var stored = false
    var startPhase = CorePhase.AWAITING_AUTH
    var userId = ""
    var codeFailure: CoreFailure? = null
    var verifyResult: CoreAuthStep = CoreAuthStep.LoggedIn("100")
    var verifyFailure: CoreFailure? = null
    var verifyGate: CompletableDeferred<Unit>? = null
    val requests = mutableListOf<Pair<String, Boolean>>()
    var logouts = 0
    var rejected: SessionRejection? = null

    override fun rejection() = rejected
    override fun hasStoredToken() = stored
    override suspend fun start() = startPhase
    override fun currentUserId() = userId
    override suspend fun requestCode(phone: String, resend: Boolean): CoreCode {
        requests += phone to resend
        codeFailure?.let { throw it }
        return CoreCode("token${requests.size}", 6)
    }
    override suspend fun verifyCode(token: String, code: String): CoreAuthStep {
        verifyGate?.await()
        verifyFailure?.let {
            verifyFailure = null
            throw it
        }
        return verifyResult
    }
    override suspend fun checkPassword(trackId: String, password: String): CoreAuthStep {
        if (password != "right") throw CoreFailure("AUTH", null)
        return CoreAuthStep.LoggedIn("100")
    }
    override suspend fun register(token: String, firstName: String, lastName: String) = CoreAuthStep.LoggedIn("100")
    override suspend fun logout() {
        logouts += 1
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class SessionManagerTest {
    private val core = FakeCore()
    private val ids = object : UserIdStore {
        override var lastUserId: String? = null
    }
    private var signedIn = mutableListOf<String>()
    private var cleared = 0
    private val freshEntries = mutableListOf<AccountLimits.Entry>()
    private val fresh get() = freshEntries.size

    private fun TestScope.session() = SessionManager(
        core,
        backgroundScope,
        ids,
        onSignedIn = { signedIn += it },
        onSignedOut = { cleared += 1 },
        onFreshSession = { freshEntries += it },
    )

    private suspend inline fun expectError(expected: OrbitleError, block: () -> Unit) {
        try {
            block()
            fail("ожидалась ошибка $expected")
        } catch (e: OrbitleError) {
            assertEquals(expected, e)
        }
    }

    @Test
    fun restoreWithoutTokenShowsLogin() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        s.restoreSession()
        assertEquals(AuthPhase.SignedOut, s.phase.value)
        assertEquals(ConnectionState.ONLINE, s.connection.value)
    }

    @Test
    fun restoreReadyEntersAndLoads() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
        assertEquals("100", ids.lastUserId)
        assertEquals(listOf("100"), signedIn)
    }

    @Test
    fun offlineWithTokenShowsCache() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.FAILED
        core.stored = true
        ids.lastUserId = "7"
        val s = session()
        s.restoreSession()
        assertEquals(AuthPhase.SignedIn("7"), s.phase.value)
        assertEquals(ConnectionState.OFFLINE, s.connection.value)
    }

    @Test
    fun startThatKeepsReconnectingShowsCacheAsConnecting() = runTest(UnconfinedTestDispatcher()) {
        // the core reports a failed first connect as RECONNECTING and retries by itself
        core.startPhase = CorePhase.RECONNECTING
        core.stored = true
        ids.lastUserId = "7"
        val s = session()
        s.restoreSession()
        assertEquals(AuthPhase.SignedIn("7"), s.phase.value)
        assertEquals(ConnectionState.CONNECTING, s.connection.value)
    }

    @Test
    fun freshNoticeFollowsCodePasswordAndRegistrationOnly() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val restored = session()
        restored.restoreSession()
        restored.observe(CorePhase.READY)
        assertEquals(AuthPhase.SignedIn("100"), restored.phase.value)
        assertEquals(0, fresh)

        restored.logout()
        restored.requestCode("+79991234567")
        restored.verifyCode("123456")
        assertEquals(1, fresh)

        restored.logout()
        core.verifyResult = CoreAuthStep.Password("track", null)
        restored.requestCode("+79991234567")
        restored.verifyCode("123456")
        assertEquals(AuthPhase.Password(null), restored.phase.value)
        assertEquals(1, fresh)
        restored.submitPassword("right")
        assertEquals(2, fresh)

        restored.logout()
        core.verifyResult = CoreAuthStep.Register("reg")
        restored.requestCode("+79991234567")
        restored.verifyCode("123456")
        assertEquals(2, fresh)
        restored.register("Иван", "")
        assertEquals(3, fresh)
        assertEquals(
            listOf(AccountLimits.Entry.LOGIN, AccountLimits.Entry.LOGIN, AccountLimits.Entry.REGISTRATION),
            freshEntries,
        )
    }

    @Test
    fun codeThenLogin() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        s.restoreSession()
        s.requestCode(" +79991234567 ")
        assertEquals(AuthPhase.CodeSent(6), s.phase.value)
        s.verifyCode("12 34 56")
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
    }

    @Test
    fun wrongCodeAndRateLimitTexts() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        s.requestCode("+79991234567")
        core.verifyFailure = CoreFailure("SERVER", "verify.code.wrong")
        expectError(OrbitleError.Rejected("Неверный код")) { s.verifyCode("111111") }
        core.verifyFailure = CoreFailure("SERVER", "too.many.attempts")
        expectError(OrbitleError.Rejected(AuthErrors.TOO_MANY_ATTEMPTS)) { s.verifyCode("111111") }
    }

    @Test
    fun expiredCodeIsRenewed() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        s.requestCode("+79991234567")
        core.verifyFailure = CoreFailure("SESSION_EXPIRED", "login.token")
        expectError(OrbitleError.codeRenewed) { s.verifyCode("111111") }
        assertEquals(listOf("+79991234567" to false, "+79991234567" to false), core.requests)
        assertEquals(AuthPhase.CodeSent(6), s.phase.value)
    }

    @Test
    fun requestCodeErrors() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        expectError(OrbitleError.Rejected("Введите номер телефона")) { s.requestCode("  ") }
        core.codeFailure = CoreFailure("NETWORK", null)
        expectError(OrbitleError.NetworkUnavailable) { s.requestCode("+79991234567") }
        core.codeFailure = CoreFailure("SERVER", "phone.invalid")
        expectError(OrbitleError.Rejected("Не удалось отправить код. Проверьте номер телефона")) { s.requestCode("+79991234567") }
    }

    @Test
    fun passwordFlow() = runTest(UnconfinedTestDispatcher()) {
        core.verifyResult = CoreAuthStep.Password("track", "подсказка")
        val s = session()
        s.requestCode("+79991234567")
        s.verifyCode("123456")
        assertEquals(AuthPhase.Password("подсказка"), s.phase.value)
        expectError(OrbitleError.Rejected("Неверный пароль")) { s.submitPassword("wrong") }
        s.submitPassword("right")
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
    }

    @Test
    fun registrationFlow() = runTest(UnconfinedTestDispatcher()) {
        core.verifyResult = CoreAuthStep.Register("reg")
        val s = session()
        s.requestCode("+79991234567")
        s.verifyCode("123456")
        assertEquals(AuthPhase.Registration, s.phase.value)
        expectError(OrbitleError.Rejected("Введите имя")) { s.register(" ", "") }
        s.register("Иван", "")
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
    }

    @Test
    fun lateAnswerAfterCancelIsIgnored() = runTest(UnconfinedTestDispatcher()) {
        core.verifyResult = CoreAuthStep.Password("track", null)
        core.verifyGate = CompletableDeferred()
        val s = session()
        s.requestCode("+79991234567")
        var error: Throwable? = null
        val job = launch { runCatching { s.verifyCode("123456") }.onFailure { error = it } }
        s.cancelLogin()
        core.verifyGate?.complete(Unit)
        job.join()
        assertEquals(OrbitleError.Cancelled, error)
        assertEquals(AuthPhase.SignedOut, s.phase.value)
    }

    @Test
    fun logoutClearsEverything() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        s.logout()
        assertEquals(AuthPhase.SignedOut, s.phase.value)
        assertEquals(1, core.logouts)
        assertEquals(1, cleared)
        assertEquals(null, ids.lastUserId)
    }

    @Test
    fun anotherAccountWipesCache() = runTest(UnconfinedTestDispatcher()) {
        ids.lastUserId = "5"
        val s = session()
        s.requestCode("+79991234567")
        s.verifyCode("123456")
        assertEquals(1, cleared)
        assertEquals("100", ids.lastUserId)
    }

    @Test
    fun rejectedTokenExpiresSession() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        core.phases.emit(CorePhase.TOKEN_REJECTED)
        assertEquals(AuthPhase.Expired(), s.phase.value)
        assertTrue(s.connection.value == ConnectionState.OFFLINE)
    }

    @Test
    fun clearedTokenWipesTheSessionAndShowsLogin() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        assertEquals("100", ids.lastUserId)
        val blocked = SessionRejection(SessionRejection.Reason.BLOCKED, title = "Заблокирован")
        core.rejected = blocked
        core.phases.emit(CorePhase.TOKEN_REJECTED)
        assertEquals(AuthPhase.Expired(blocked), s.phase.value)
        // Токен стёрт: данные прежнего сеанса уходят вместе с ним.
        assertEquals(1, cleared)
        assertEquals(null, ids.lastUserId)
    }

    @Test
    fun rejectionAtStartGoesStraightToLogin() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        ids.lastUserId = "100"
        core.startPhase = CorePhase.TOKEN_REJECTED
        core.rejected = SessionRejection(SessionRejection.Reason.TOKEN)
        val s = session()
        s.restoreSession()
        assertEquals(AuthPhase.Expired(SessionRejection(SessionRejection.Reason.TOKEN)), s.phase.value)
        assertEquals(1, cleared)
        assertEquals(null, ids.lastUserId)
    }

    @Test
    fun floodKeepsTheSessionAndCanRetry() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        val flood = SessionRejection(SessionRejection.Reason.FLOOD, localizedMessage = "Попробуйте позже")
        core.rejected = flood
        core.phases.emit(CorePhase.TOKEN_REJECTED)
        assertEquals(AuthPhase.Throttled(flood), s.phase.value)
        // Токен цел: ничего не стирается, id остаётся.
        assertEquals(0, cleared)
        assertEquals("100", ids.lastUserId)
        // Повтор входа тем же токеном.
        core.rejected = null
        s.retryLogin()
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
    }

    @Test
    fun floodThenLogoutSignsOut() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        ids.lastUserId = "100"
        core.startPhase = CorePhase.TOKEN_REJECTED
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        val s = session()
        s.restoreSession()
        assertTrue(s.phase.value is AuthPhase.Throttled)
        s.logout()
        assertEquals(AuthPhase.SignedOut, s.phase.value)
        assertEquals(1, core.logouts)
        assertEquals(null, ids.lastUserId)
    }

    @Test
    fun reconnectingShowsConnecting() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        val s = session()
        s.restoreSession()
        core.phases.emit(CorePhase.RECONNECTING)
        assertEquals(ConnectionState.CONNECTING, s.connection.value)
        core.phases.emit(CorePhase.READY)
        assertEquals(ConnectionState.ONLINE, s.connection.value)
    }
}
