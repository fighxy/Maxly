package app.orbitle.data

import app.orbitle.domain.AuthPhase
import app.orbitle.domain.AuthService
import app.orbitle.domain.isFreshLogin
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Где сессия помнит id последнего вошедшего пользователя. */
interface UserIdStore {
    var lastUserId: String?
}

/**
 * Сессия приложения: шаги входа через ядро. Токен хранит само ядро.
 *
 * Попытка входа нумеруется ([attempt]). `cancelLogin` и `logout` начинают новую попытку,
 * поэтому поздний ответ ядра из старой попытки не меняет шаг, а метод бросает
 * [OrbitleError.Cancelled]. Исключение — успешный вход: ядро уже сохранило токен.
 */
class SessionManager(
    private val core: CoreGateway,
    private val scope: CoroutineScope,
    private val userIds: UserIdStore,
    /** Вход выполнен: репозитории грузят чаты. */
    private val onSignedIn: suspend (userId: String) -> Unit = {},
    /** Выход или смена аккаунта: репозитории стирают кэш. */
    private val onSignedOut: suspend () -> Unit = {},
    /** Вход с шага кода, пароля или регистрации, а не восстановление сохранённого сеанса. */
    private val onFreshSession: () -> Unit = {},
) : AuthService {

    private val _phase = MutableStateFlow<AuthPhase>(AuthPhase.Restoring)
    override val phase: StateFlow<AuthPhase> = _phase.asStateFlow()

    private val _connection = MutableStateFlow(ConnectionState.CONNECTING)
    override val connection: StateFlow<ConnectionState> = _connection.asStateFlow()

    private var phone = ""
    private var codeToken: String? = null
    private var trackId: String? = null
    private var registerToken: String? = null
    private var attempt = 0
    private var logouts = 0
    private var isLoggingOut = false
    private var coreWatch: Job? = null

    private val isAuthorized: Boolean get() = _phase.value is AuthPhase.SignedIn
    private val signedInUserId: String? get() = (_phase.value as? AuthPhase.SignedIn)?.userId

    override suspend fun restoreSession() {
        val epoch = logouts
        _phase.value = AuthPhase.Restoring
        watchCore()
        val stored = core.hasStoredToken()
        val remembered = userIds.lastUserId.orEmpty()
        val started = try {
            core.start()
        } catch (e: Throwable) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            null
        }
        // Пока ядро подключалось, фазу мог сменить поток ядра (отказ токена) или выход.
        if (_phase.value != AuthPhase.Restoring) return
        when (started) {
            CorePhase.READY -> {
                _connection.value = ConnectionState.ONLINE
                val id = core.currentUserId()
                enter(id.ifEmpty { remembered }, epoch)
            }
            CorePhase.TOKEN_REJECTED -> expire()
            CorePhase.AWAITING_AUTH -> {
                _connection.value = ConnectionState.ONLINE
                _phase.value = AuthPhase.SignedOut
            }
            else -> {
                if (started == null || started == CorePhase.FAILED || started == CorePhase.IDLE) {
                    _connection.value = ConnectionState.OFFLINE
                }
                _phase.value = if (stored) AuthPhase.SignedIn(remembered) else AuthPhase.SignedOut
            }
        }
    }

    override suspend fun requestCode(phone: String) {
        val number = phone.trim()
        if (number.isEmpty()) throw OrbitleError.Rejected("Введите номер телефона")
        if (isAuthorized) throw OrbitleError.InvalidRequest
        val generation = attempt
        val code = try {
            core.requestCode(number, resend = false)
        } catch (e: Throwable) {
            throw AuthErrors.map(e, AuthStep.REQUEST_CODE)
        }
        ensureCurrent(generation)
        this.phone = number
        codeToken = code.token
        trackId = null
        registerToken = null
        _phase.value = AuthPhase.CodeSent(code.codeLength)
    }

    override suspend fun resendCode() {
        if (phone.isEmpty() || codeToken == null) throw OrbitleError.InvalidRequest
        val generation = attempt
        val code = try {
            core.requestCode(phone, resend = true)
        } catch (e: Throwable) {
            throw AuthErrors.map(e, AuthStep.REQUEST_CODE)
        }
        ensureCurrent(generation)
        codeToken = code.token
        _phase.value = AuthPhase.CodeSent(code.codeLength)
    }

    override suspend fun verifyCode(code: String) {
        val digits = code.filterNot { it.isWhitespace() }
        if (digits.isEmpty()) throw OrbitleError.Rejected("Введите код из SMS")
        val token = codeToken ?: throw OrbitleError.InvalidRequest
        val generation = attempt
        val epoch = logouts
        val step = try {
            core.verifyCode(token, digits)
        } catch (e: Throwable) {
            if (AuthErrors.isExpiredCode(e) && renewCode(generation)) throw OrbitleError.codeRenewed
            throw AuthErrors.map(e, AuthStep.VERIFY_CODE)
        }
        apply(step, generation, epoch)
    }

    /** Устаревший код заменяется новым на тот же номер. `false`, если не вышло. */
    private suspend fun renewCode(generation: Int): Boolean {
        if (phone.isEmpty() || generation != attempt) return false
        val code = runCatching { core.requestCode(phone, resend = false) }.getOrNull() ?: return false
        if (generation != attempt || isLoggingOut) return false
        codeToken = code.token
        _phase.value = AuthPhase.CodeSent(code.codeLength)
        return true
    }

    override suspend fun submitPassword(password: String) {
        if (password.isEmpty()) throw OrbitleError.Rejected("Введите пароль")
        val track = trackId ?: throw OrbitleError.InvalidRequest
        val generation = attempt
        val epoch = logouts
        val step = try {
            core.checkPassword(track, password)
        } catch (e: Throwable) {
            throw AuthErrors.map(e, AuthStep.PASSWORD)
        }
        apply(step, generation, epoch)
    }

    override suspend fun register(firstName: String, lastName: String) {
        val first = firstName.trim()
        val last = lastName.trim()
        if (first.isEmpty()) throw OrbitleError.Rejected("Введите имя")
        val token = registerToken ?: throw OrbitleError.InvalidRequest
        val generation = attempt
        val epoch = logouts
        val step = try {
            core.register(token, first, last)
        } catch (e: Throwable) {
            throw AuthErrors.map(e, AuthStep.REGISTER)
        }
        apply(step, generation, epoch)
    }

    override suspend fun cancelLogin() {
        if (isAuthorized) return
        attempt += 1
        forgetLoginAttempt()
        _phase.value = AuthPhase.SignedOut
    }

    override suspend fun logout() {
        attempt += 1
        logouts += 1
        isLoggingOut = true
        try {
            runCatching { core.logout() }
            onSignedOut()
            userIds.lastUserId = null
            forgetLoginAttempt()
            _phase.value = AuthPhase.SignedOut
        } finally {
            isLoggingOut = false
        }
    }

    private fun ensureCurrent(generation: Int) {
        if (generation != attempt || isLoggingOut) throw OrbitleError.Cancelled
    }

    private fun forgetLoginAttempt() {
        codeToken = null
        trackId = null
        registerToken = null
        phone = ""
    }

    private suspend fun apply(step: CoreAuthStep, generation: Int, epoch: Int) {
        when (step) {
            is CoreAuthStep.LoggedIn -> {
                // Токен уже у ядра: отменённая попытка всё равно входит. Выход важнее.
                if (isLoggingOut || epoch != logouts) throw OrbitleError.Cancelled
                enter(step.userId.ifEmpty { core.currentUserId() }, epoch)
            }
            is CoreAuthStep.Password -> {
                ensureCurrent(generation)
                trackId = step.trackId
                _phase.value = AuthPhase.Password(step.hint)
            }
            is CoreAuthStep.Register -> {
                ensureCurrent(generation)
                registerToken = step.token
                _phase.value = AuthPhase.Registration
            }
        }
    }

    /** Вход. Чужой user id стирает кэш предыдущего аккаунта. */
    private suspend fun enter(userId: String, epoch: Int) {
        if (epoch != logouts) return
        val previous = userIds.lastUserId
        val id = userId.ifEmpty { previous.orEmpty() }
        val fresh = _phase.value.isFreshLogin()
        if (previous != null && id.isNotEmpty() && previous != id) {
            onSignedOut()
            if (epoch != logouts) return
        }
        if (id.isNotEmpty()) userIds.lastUserId = id
        forgetLoginAttempt()
        _phase.value = AuthPhase.SignedIn(id)
        runCatching { onSignedIn(id) }
        if (fresh) runCatching { onFreshSession() }
    }

    private fun expire() {
        forgetLoginAttempt()
        _phase.value = AuthPhase.Expired
    }

    private fun watchCore() {
        if (coreWatch != null) return
        coreWatch = scope.launch { core.phases.collect { observe(it) } }
    }

    /** Фаза ядра после старта: индикатор соединения и отказ токена. */
    internal suspend fun observe(next: CorePhase) {
        when (next) {
            CorePhase.TOKEN_REJECTED -> {
                _connection.value = ConnectionState.OFFLINE
                // Во время входа по коду старый отказ токена шаг не сбрасывает.
                if (isAuthorized || _phase.value == AuthPhase.Restoring) expire()
            }
            CorePhase.READY -> {
                _connection.value = ConnectionState.ONLINE
                val current = signedInUserId ?: return
                val id = core.currentUserId()
                if (id.isNotEmpty() && id != current) {
                    // Кэш показывался под запомненным id, а ядро вошло другим аккаунтом.
                    enter(id, logouts)
                } else {
                    runCatching { onSignedIn(current) }
                }
            }
            CorePhase.CONNECTING, CorePhase.RECONNECTING -> _connection.value = ConnectionState.CONNECTING
            CorePhase.FAILED, CorePhase.IDLE -> _connection.value = ConnectionState.OFFLINE
            CorePhase.AWAITING_AUTH -> _connection.value = ConnectionState.ONLINE
        }
    }
}
