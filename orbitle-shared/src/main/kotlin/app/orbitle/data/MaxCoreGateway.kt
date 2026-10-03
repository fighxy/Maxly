package app.orbitle.data

import com.max.core.auth.CodeRequestType
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

    override val phases: Flow<CorePhase> = client.state.map(::phaseOf).distinctUntilChanged()

    override fun hasStoredToken(): Boolean = runCatching { client.hasStoredToken }.getOrDefault(false)

    override suspend fun start(): CorePhase = call { phaseOf(client.start()) }

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
        fun phaseOf(state: ClientState): CorePhase = when (state) {
            ClientState.Idle -> CorePhase.IDLE
            ClientState.Connecting -> CorePhase.CONNECTING
            is ClientState.AwaitingAuth -> CorePhase.AWAITING_AUTH
            is ClientState.Ready -> CorePhase.READY
            is ClientState.Reconnecting -> CorePhase.RECONNECTING
            is ClientState.TokenRejected -> CorePhase.TOKEN_REJECTED
            is ClientState.Failed -> CorePhase.FAILED
        }

        /** Вызов ядра с переводом исключения в [CoreFailure]. Отмена проходит как есть. */
        suspend fun <T> call(block: suspend () -> T): T = try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: CoreFailure) {
            throw e
        } catch (e: Throwable) {
            throw failureOf(e)
        }

        fun failureOf(e: Throwable): CoreFailure {
            val error = e.toMaxError()
            return CoreFailure(error.kind.name, error.errorKey, error.message)
        }
    }
}
