package app.maxly.data

import app.maxly.domain.AccountLimits
import app.maxly.domain.AuthPhase
import app.maxly.domain.ConnectionState
import app.maxly.domain.MaxlyError
import app.maxly.domain.SessionRejection
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
    var startFailure: CoreFailure? = null
    override suspend fun start(): CorePhase {
        startFailure?.let { throw it }
        return startPhase
    }
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

    private suspend inline fun expectError(expected: MaxlyError, block: () -> Unit) {
        try {
            block()
            fail("ожидалась ошибка $expected")
        } catch (e: MaxlyError) {
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
        expectError(MaxlyError.Rejected("Неверный код")) { s.verifyCode("111111") }
        core.verifyFailure = CoreFailure("SERVER", "too.many.attempts")
        expectError(MaxlyError.Rejected(AuthErrors.TOO_MANY_ATTEMPTS)) { s.verifyCode("111111") }
    }

    @Test
    fun expiredCodeIsRenewed() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        s.requestCode("+79991234567")
        core.verifyFailure = CoreFailure("SESSION_EXPIRED", "login.token")
        expectError(MaxlyError.codeRenewed) { s.verifyCode("111111") }
        assertEquals(listOf("+79991234567" to false, "+79991234567" to false), core.requests)
        assertEquals(AuthPhase.CodeSent(6), s.phase.value)
    }

    @Test
    fun requestCodeErrors() = runTest(UnconfinedTestDispatcher()) {
        val s = session()
        expectError(MaxlyError.Rejected("Введите номер телефона")) { s.requestCode("  ") }
        core.codeFailure = CoreFailure("NETWORK", null)
        expectError(MaxlyError.NetworkUnavailable) { s.requestCode("+79991234567") }
        core.codeFailure = CoreFailure("SERVER", "phone.invalid")
        expectError(MaxlyError.Rejected("Не удалось отправить код. Проверьте номер телефона")) { s.requestCode("+79991234567") }
    }

    @Test
    fun passwordFlow() = runTest(UnconfinedTestDispatcher()) {
        core.verifyResult = CoreAuthStep.Password("track", "подсказка")
        val s = session()
        s.requestCode("+79991234567")
        s.verifyCode("123456")
        assertEquals(AuthPhase.Password("подсказка"), s.phase.value)
        expectError(MaxlyError.Rejected("Неверный пароль")) { s.submitPassword("wrong") }
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
        expectError(MaxlyError.Rejected("Введите имя")) { s.register(" ", "") }
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
        assertEquals(MaxlyError.Cancelled, error)
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
    fun floodKeepsTheChatListWithABannerAndCanRetry() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        val flood = SessionRejection(SessionRejection.Reason.FLOOD, localizedMessage = "Попробуйте позже")
        core.rejected = flood
        core.phases.emit(CorePhase.TOKEN_REJECTED)
        // Не экран входа: список чатов остаётся, без сети и с баннером.
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
        assertEquals(flood, s.throttled.value)
        assertEquals(ConnectionState.OFFLINE, s.connection.value)
        // Токен цел: ничего не стирается, id остаётся.
        assertEquals(0, cleared)
        assertEquals("100", ids.lastUserId)
        // Повтор входа тем же токеном: сервер пустил — баннер уходит, чаты обновляются.
        signedIn.clear()
        core.rejected = null
        s.retryLogin()
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
        assertNull(s.throttled.value)
        assertEquals(ConnectionState.ONLINE, s.connection.value)
        assertEquals(listOf("100"), signedIn)
    }

    @Test
    fun floodAtStartOpensTheSavedChatList() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        ids.lastUserId = "100"
        core.startPhase = CorePhase.TOKEN_REJECTED
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        val s = session()
        s.restoreSession()
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
        assertEquals(SessionRejection(SessionRejection.Reason.FLOOD), s.throttled.value)
        assertEquals(ConnectionState.OFFLINE, s.connection.value)
        assertEquals(0, cleared)
        // Сеть не трогали до ответа сервера: загрузка чатов с сервера не начиналась.
        assertTrue(signedIn.isEmpty())
    }

    @Test
    fun repeatedFloodUpdatesTheBanner() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        ids.lastUserId = "100"
        core.startPhase = CorePhase.TOKEN_REJECTED
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        val s = session()
        s.restoreSession()
        val again = SessionRejection(SessionRejection.Reason.FLOOD, title = "Подождите ещё")
        core.rejected = again
        s.retryLogin()
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
        assertEquals(again, s.throttled.value)
        assertEquals(ConnectionState.OFFLINE, s.connection.value)
        // Без сети повтор оставляет баннер.
        core.startFailure = CoreFailure("network", null)
        s.retryLogin()
        assertEquals(again, s.throttled.value)
        assertEquals(ConnectionState.OFFLINE, s.connection.value)
    }

    @Test
    fun reconnectByTheCoreRemovesTheBanner() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        ids.lastUserId = "100"
        core.startPhase = CorePhase.TOKEN_REJECTED
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        val s = session()
        s.restoreSession()
        core.phases.emit(CorePhase.READY)
        assertNull(s.throttled.value)
        assertEquals(ConnectionState.ONLINE, s.connection.value)
        assertEquals(AuthPhase.SignedIn("100"), s.phase.value)
    }

    @Test
    fun clearedTokenAfterFloodGoesToLogin() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.READY
        core.userId = "100"
        val s = session()
        s.restoreSession()
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        core.phases.emit(CorePhase.TOKEN_REJECTED)
        val token = SessionRejection(SessionRejection.Reason.TOKEN)
        core.rejected = token
        core.startPhase = CorePhase.TOKEN_REJECTED
        s.retryLogin()
        assertEquals(AuthPhase.Expired(token), s.phase.value)
        assertNull(s.throttled.value)
        assertEquals(1, cleared)
    }

    @Test
    fun floodThenLogoutSignsOut() = runTest(UnconfinedTestDispatcher()) {
        core.stored = true
        ids.lastUserId = "100"
        core.startPhase = CorePhase.TOKEN_REJECTED
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        val s = session()
        s.restoreSession()
        assertTrue(s.throttled.value != null)
        s.logout()
        assertEquals(AuthPhase.SignedOut, s.phase.value)
        assertNull(s.throttled.value)
        assertEquals(1, core.logouts)
        assertEquals(null, ids.lastUserId)
    }

    @Test
    fun floodDuringSmsLoginKeepsTheStep() = runTest(UnconfinedTestDispatcher()) {
        core.startPhase = CorePhase.AWAITING_AUTH
        val s = session()
        s.restoreSession()
        s.requestCode("+79991234567")
        core.rejected = SessionRejection(SessionRejection.Reason.FLOOD)
        core.phases.emit(CorePhase.TOKEN_REJECTED)
        assertTrue(s.phase.value is AuthPhase.CodeSent)
        assertNull(s.throttled.value)
        // Без временного отказа повторять нечего.
        s.retryLogin()
        assertTrue(s.phase.value is AuthPhase.CodeSent)
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
