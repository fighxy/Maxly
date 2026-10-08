package app.orbitle.data

import app.orbitle.domain.SessionRejection
import com.max.core.auth.CodeRequestType
import com.max.core.auth.LoginRejection
import com.max.core.auth.VerifyResult
import com.max.core.toMaxError
import com.max.shared.ClientState
import com.max.shared.MaxClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** [CoreGateway] над `MaxClient` ядра. Любое исключение ядра становится [CoreFailure]. */
class MaxCoreGateway(private val client: MaxClient) : CoreGateway {

    /** Отказ из последнего [ClientState.TokenRejected]: состояние ядра могло уже смениться. */
    @Volatile private var lastRejection: SessionRejection? = null

    override val phases: Flow<CorePhase> = client.state.map { remember(it); phaseOf(it) }.distinctUntilChanged()

    override fun hasStoredToken(): Boolean = runCatching { client.hasStoredToken }.getOrDefault(false)

    override suspend fun start(): CorePhase = call { client.start().also(::remember).let(::phaseOf) }

    override fun rejection(): SessionRejection? =
        (client.state.value as? ClientState.TokenRejected)?.let(::rejectionOf) ?: lastRejection

    private fun remember(state: ClientState) {
        if (state is ClientState.TokenRejected) lastRejection = rejectionOf(state)
    }

    override fun currentUserId(): String = client.userId.value?.toString().orEmpty()

    override suspend fun requestCode(phone: String, resend: Boolean): CoreCode = call {
        val r = client.requestCode(phone, if (resend) CodeRequestType.RESEND else CodeRequestType.START_AUTH)
        CoreCode(r.token, r.codeLength)
    }

    override suspend fun verifyCode(token: String, code: String): CoreAuthStep = call {
        when (val r = client.verifyCode(token, code)) {
            is VerifyResult.LoggedIn -> CoreAuthStep.LoggedIn((r.userId ?: client.userId.value)?.toString().orEmpty())
            is VerifyResult.PasswordRequired -> CoreAuthStep.Password(r.trackId, r.hint?.takeIf { it.isNotBlank() })
            is VerifyResult.RegistrationRequired -> CoreAuthStep.Register(r.registerToken)
        }
    }

    override suspend fun checkPassword(trackId: String, password: String): CoreAuthStep = call {
        val r = client.checkPassword(trackId, password)
        CoreAuthStep.LoggedIn((r.userId ?: client.userId.value)?.toString().orEmpty())
    }

    override suspend fun register(token: String, firstName: String, lastName: String): CoreAuthStep = call {
        val r = client.register(token, firstName, lastName.ifBlank { null })
        CoreAuthStep.LoggedIn((r.userId ?: client.userId.value)?.toString().orEmpty())
    }

    override suspend fun logout() = call { client.logout() }

    companion object {
        /** Отказ ядра во входе — в доменный вид: код, стёрт ли токен, тексты сервера. */
        fun rejectionOf(state: ClientState.TokenRejected): SessionRejection = SessionRejection(
            reason = when (state.reason) {
                LoginRejection.TOKEN -> SessionRejection.Reason.TOKEN
                LoginRejection.BLOCKED -> SessionRejection.Reason.BLOCKED
                LoginRejection.FLOOD -> SessionRejection.Reason.FLOOD
            },
            tokenCleared = state.tokenCleared,
            title = state.title,
            localizedMessage = state.localizedMessage,
            description = state.description,
        )

        fun phaseOf(state: ClientState): CorePhase = when (state) {
            ClientState.Idle -> CorePhase.IDLE
            ClientState.Connecting -> CorePhase.CONNECTING
            is ClientState.AwaitingAuth -> CorePhase.AWAITING_AUTH
            is ClientState.Ready -> CorePhase.READY
            is ClientState.Reconnecting -> CorePhase.RECONNECTING
            is ClientState.TokenRejected -> CorePhase.TOKEN_REJECTED
            is ClientState.Failed -> CorePhase.FAILED
        }

        /**
         * Вызов ядра с переводом исключения в [CoreFailure]. Отмена проходит как есть.
         * Отказ `too.many.requests` включает паузу [ServerRateLimit] для чтений [read].
         */
        suspend fun <T> call(block: suspend () -> T): T = try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: CoreFailure) {
            // Уже переведена вложенным вызовом (и пауза уже учтена) или это отказ паузы.
            throw e
        } catch (e: Throwable) {
            val failure = failureOf(e)
            if (ServerRateLimit.isLimit(failure.key)) ServerRateLimit.shared.noteLimited()
            throw failure
        }

        /**
         * Фоновое чтение (история, комментарии, общие медиа, карточки, реакции, звонки): во время
         * паузы после `too.many.requests` сразу получает тот же отказ, не дёргая сервер.
         */
        suspend fun <T> read(limit: ServerRateLimit = ServerRateLimit.shared, block: suspend () -> T): T {
            if (limit.remainingMs() != null) throw CoreFailure("SERVER", ServerRateLimit.KEY, "пауза после too.many.requests")
            val value = call(block)
            limit.noteSuccess()
            return value
        }

        /**
         * Чтение, которого ждёт пользователь (история только что открытого чата): уходит и во
         * время паузы. Отказ сервера, как у [read], продлевает паузу для фоновых чтений, удача —
         * сбрасывает счёт отказов.
         */
        suspend fun <T> readNow(limit: ServerRateLimit = ServerRateLimit.shared, block: suspend () -> T): T {
            val value = call(block)
            limit.noteSuccess()
            return value
        }

        fun failureOf(e: Throwable): CoreFailure {
            val error = e.toMaxError()
            val text = error.serverText?.trim()?.takeIf { it.isNotEmpty() }
            return CoreFailure(error.kind.name, error.errorKey, error.message, text)
        }
    }
}
