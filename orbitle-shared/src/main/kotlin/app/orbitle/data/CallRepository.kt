package app.orbitle.data

import app.orbitle.domain.CallOutcome
import app.orbitle.domain.CallRecord
import com.max.core.calls.CallLink
import com.max.core.calls.CallLogEntry
import com.max.core.state.MaxState
import com.max.shared.MaxClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** История звонков аккаунта. */
interface CallRepository {
    /** `null`, пока история ни разу не загружалась. */
    val calls: StateFlow<List<CallRecord>?>
    suspend fun refresh()
    /** Удаляет звонки на сервере (`VIDEO_CHAT_DELETE_HISTORY`) и из журнала. */
    suspend fun delete(ids: List<String>)
    /** Новый групповой звонок: ссылка, по которой в него входят. */
    suspend fun createLink(): String
    fun clear()
}

class CoreCallRepository(private val client: MaxClient) : CallRepository {
    private val _calls = MutableStateFlow<List<CallRecord>?>(null)
    override val calls: StateFlow<List<CallRecord>?> = _calls.asStateFlow()

    override suspend fun refresh() {
        val me = client.store.state.value.me
        val entries = MaxCoreGateway.read { client.api.calls.history() }
        val unknown = entries.mapNotNull { it.peerId(me) }.distinct().filter { it !in client.store.state.value.users }
        if (unknown.isNotEmpty()) runCatching { MaxCoreGateway.read { client.loadUsers(unknown.take(100)) } }
        val state = client.store.state.value
        _calls.value = entries.map { record(it, me, state) }
    }

    override suspend fun delete(ids: List<String>) {
        val valid = ids.mapNotNull { it.toLongOrNull() }
        if (valid.isEmpty()) return
        MaxCoreGateway.call { client.api.calls.deleteHistory(valid) }
        val removed = valid.map { it.toString() }.toSet()
        _calls.value = _calls.value?.filterNot { it.id in removed }
    }

    override suspend fun createLink(): String = MaxCoreGateway.call {
        val created = client.api.calls.createConference()
        val token = CallLink.token(created.joinLink) ?: throw IllegalStateException("no call link")
        CallLink.url(token)
    }

    override fun clear() {
        _calls.value = null
    }

    companion object {
        /** Исход как у iOS-клиента: свой сброшенный — отменённый, отклонённый собеседником — отклонённый. */
        fun record(entry: CallLogEntry, me: Long?, state: MaxState): CallRecord {
            val outgoing = me != null && entry.senderId == me
            val outcome = if (outgoing) {
                when (entry.hangupType) {
                    "REJECTED" -> CallOutcome.DECLINED
                    "CANCELED" -> CallOutcome.CANCELLED
                    else -> if (entry.duration > 0) CallOutcome.ANSWERED else CallOutcome.CANCELLED
                }
            } else {
                if (entry.isMissed(me)) CallOutcome.MISSED else CallOutcome.ANSWERED
            }
            val peerId = entry.peerId(me)
            val peer = peerId?.let { state.users[it] }
            val isGroup = peer == null && entry.contactIds.size > 1
            val chatId = entry.chatId?.toString()
            return CallRecord(
                id = entry.messageId.toString(),
                peerId = peerId?.toString() ?: chatId.orEmpty(),
                title = peer?.displayName?.takeIf { it.isNotBlank() } ?: if (isGroup) "Групповой звонок" else "Звонок",
                avatarUrl = peer?.baseUrl?.takeIf { it.isNotBlank() },
                isGroup = isGroup,
                chatId = chatId?.takeIf { it.isNotEmpty() },
                outgoing = outgoing,
                outcome = outcome,
                isVideo = entry.isVideo,
                timeMs = entry.time,
                durationMs = entry.duration,
            )
        }
    }
}
