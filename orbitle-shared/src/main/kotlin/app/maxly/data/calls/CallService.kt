package app.maxly.data.calls

import app.maxly.data.MaxCoreGateway
import app.maxly.domain.CallConnection
import app.maxly.domain.CallIceServer
import app.maxly.domain.CallLinkPreview
import app.maxly.domain.IncomingCall
import app.maxly.domain.MaxlyError
import com.max.core.calls.CallLink
import com.max.core.calls.CallSignaling
import com.max.core.calls.Ws2ClientInfo
import com.max.core.calls.ws2UrlFromEndpoint
import com.max.core.events.MaxEvent
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Звонки через основной сервер Max: начать, войти по ссылке, создать ссылку и слушать входящие.
 * Сам разговор идёт через сервер звонков ([CallControl]).
 */
interface CallService {
    /** Позвонить пользователю Max. Сервер отвечает адресом ws2, у собеседника начинает звонить. */
    suspend fun startCall(peerId: String, isVideo: Boolean): CallConnection

    /** Войти в групповой звонок по ссылке `https://max.ru/joincall/…` или её токену. */
    suspend fun join(link: String, isVideo: Boolean): CallConnection

    /** Новый групповой звонок; создатель входит в него по этой же ссылке. */
    suspend fun createLink(): String

    /** Что за звонок за ссылкой; `null`, если ссылка не ведёт в звонок. */
    suspend fun preview(link: String): CallLinkPreview? = null

    /** Входящие звонки, пока подписка жива. */
    fun incomingCalls(): Flow<IncomingCall> = emptyFlow()

    /**
     * Отклонить входящий на сервере (`VIDEO_CHAT_HANGUP` 167, `REJECTED`). Ответ — `error` сервера,
     * `null` — отбой принят. По умолчанию ничего не шлёт.
     */
    suspend fun reject(conversationId: String, peerId: String?): String? = null
}

/** Звонки через ядро: 78 начать, 166 войти по ссылке, 76/84 ссылка, 89 описание ссылки, 167 отклонить, пуш 137. */
class CoreCallService(private val client: MaxClient) : CallService {
    override suspend fun reject(conversationId: String, peerId: String?): String? =
        MaxCoreGateway.call { client.rejectIncomingCall(conversationId, peerId?.takeIf { it.isNotEmpty() }) }

    override suspend fun startCall(peerId: String, isVideo: Boolean): CallConnection {
        val callee = peerId.toLongOrNull() ?: throw MaxlyError.InvalidRequest
        val signal = MaxCoreGateway.call { client.api.calls.initiateCall(callee, isVideo, client.device.deviceId) }
        return connection(signal, joinLink = null)
    }

    override suspend fun join(link: String, isVideo: Boolean): CallConnection {
        val token = CallLink.token(link.trim()) ?: throw MaxlyError.InvalidRequest
        val signal = MaxCoreGateway.call { client.api.calls.joinByLink(token, isVideo, client.device.deviceId) }
        return connection(signal, joinLink = CallLink.url(token))
    }

    override suspend fun createLink(): String = MaxCoreGateway.call {
        val created = client.api.calls.createConference()
        val token = CallLink.token(created.joinLink) ?: throw IllegalStateException("no call link")
        CallLink.url(token)
    }

    override suspend fun preview(link: String): CallLinkPreview? = MaxCoreGateway.call {
        client.api.calls.linkInfo(link)?.let {
            CallLinkPreview(CallLink.url(it.token), it.callName?.takeIf(String::isNotEmpty), it.participantsCount, it.isVideo)
        }
    }

    /** Входящие с читаемым `vcp`. Незнакомый звонящий ждёт свой профиль до 3 с, чтобы было имя. */
    override fun incomingCalls(): Flow<IncomingCall> = client.events.all
        .filterIsInstance<MaxEvent.CallStart>()
        .mapNotNull { event ->
            val params = event.params ?: return@mapNotNull null
            if (event.callerId !in client.store.state.value.users) {
                withTimeoutOrNull(3_000) { runCatching { client.loadUsers(listOf(event.callerId)) } }
            }
            val caller = client.store.state.value.users[event.callerId]
            val ice = buildList {
                params.stun?.takeIf { it.isNotEmpty() }?.let { add(CallIceServer(listOf(it))) }
                if (params.turn.isNotEmpty()) add(CallIceServer(params.turn, params.turnUser, params.turnPassword))
            }
            val isVideo = event.type == "VIDEO" || params.isVideo
            IncomingCall(
                conversationId = event.conversationId,
                callerId = event.callerId.toString(),
                callerName = caller?.displayName.orEmpty(),
                callerAvatarUrl = caller?.baseUrl?.takeIf { it.isNotBlank() },
                chatId = event.chatId?.toString(),
                isVideo = isVideo,
                connection = CallConnection(
                    conversationId = event.conversationId,
                    signalingUrl = params.ws2Url(event.conversationId, Ws2ClientInfo.forCalls(client.device.userAgent)),
                    selfId = params.userId(),
                    iceServers = ice,
                    isVideo = isVideo,
                ),
                expiresAtMs = params.expiresAt?.let { it * 1000 },
            )
        }

    private fun connection(signal: CallSignaling, joinLink: String?): CallConnection {
        val url = ws2UrlFromEndpoint(signal.endpoint, Ws2ClientInfo.forCalls(client.device.userAgent))
        if (!url.startsWith("ws")) {
            CallLog.warning("Сервер дал адрес звонка не ws")
            throw MaxlyError.InvalidRequest
        }
        return CallConnection(
            conversationId = signal.conversationId,
            signalingUrl = url,
            selfId = signal.callsUserId,
            isVideo = signal.isVideo,
            joinLink = joinLink,
        )
    }
}
