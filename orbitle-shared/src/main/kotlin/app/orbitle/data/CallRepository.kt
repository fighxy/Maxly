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
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock

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

/**
 * История звонков из журнала `CALL_HISTORY` 163 с пушами 165; если 163 не ответил — прежний
 * `VIDEO_CHAT_HISTORY` 79. 163 — курсор: после первой загрузки сервер шлёт только изменения,
 * а 165 приходит сам, поэтому вкладка обновляется без перезапроса всего журнала. 79 — это
 * сообщения с вложением `CALL`, у них нет ни курсора, ни пуша.
 */
class CoreCallRepository(
    private val client: MaxClient,
    scope: kotlinx.coroutines.CoroutineScope? = null,
) : CallRepository {
    private val _calls = MutableStateFlow<List<CallRecord>?>(null)
    override val calls: StateFlow<List<CallRecord>?> = _calls.asStateFlow()
    private val lock = kotlinx.coroutines.sync.Mutex()
    private var log = app.orbitle.data.calls.CallHistoryLog()

    init {
        scope?.launch {
            client.events.all.filterIsInstance<com.max.core.events.MaxEvent.CallHistoryChanged>().collect { event ->
                val resync = lock.withLock {
                    val result = app.orbitle.data.calls.CallHistorySync.push(log, event.sync, event.prevSync, event.action, event.items, event.historyIds)
                    if (!result.resync) {
                        log = result.log
                        publish()
                    }
                    result.resync && log.loaded
                }
                if (resync) runCatching { syncLog() }
            }
        }
    }

    override suspend fun refresh() {
        try {
            syncLog()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            app.orbitle.data.calls.CallLog.warning("163 не ответил, журнал из 79: $e")
            legacyRefresh()
        }
    }

    /** Запрос 163 с сохранённым курсором (первый раз `0`) и правка журнала по ответу. */
    private suspend fun syncLog() {
        val cursor = lock.withLock { if (log.loaded) log.sync else 0L }
        val page = MaxCoreGateway.read { client.callHistory(cursor) }
        loadUnknownUsers(page.items.flatMap { item -> listOfNotNull(item.callerId.takeIf { it != 0L }, dialogPeer(item)) })
        lock.withLock {
            log = app.orbitle.data.calls.CallHistorySync.page(log, page)
            publish()
        }
    }

    private fun publish() {
        val state = client.store.state.value
        _calls.value = log.items.map { item(it, state.me, state) }
    }

    private fun dialogPeer(item: com.max.core.calls.CallHistoryItem): Long? {
        val state = client.store.state.value
        val chat = state.chats[item.chatId] ?: return null
        return ChatMapping.dialogPeer(chat, state.me)
    }

    private suspend fun loadUnknownUsers(ids: List<Long>) {
        val unknown = ids.distinct().filter { it !in client.store.state.value.users }
        if (unknown.isNotEmpty()) runCatching { MaxCoreGateway.read { client.loadUsers(unknown.take(100)) } }
    }

    private suspend fun legacyRefresh() {
        val me = client.store.state.value.me
        val entries = MaxCoreGateway.read { client.api.calls.history() }
        loadUnknownUsers(entries.mapNotNull { it.peerId(me) })
        val state = client.store.state.value
        _calls.value = entries.map { record(it, me, state) }
    }

    override suspend fun delete(ids: List<String>) {
        val valid = ids.mapNotNull { it.toLongOrNull() }
        if (valid.isEmpty()) return
        MaxCoreGateway.call { client.api.calls.deleteHistory(valid) }
        val removed = valid.map { it.toString() }.toSet()
        lock.withLock { log = app.orbitle.data.calls.CallHistorySync.without(log, removed) }
        _calls.value = _calls.value?.filterNot { it.id in removed }
    }

    override suspend fun createLink(): String = MaxCoreGateway.call {
        val created = client.api.calls.createConference()
        val token = CallLink.token(created.joinLink) ?: throw IllegalStateException("no call link")
        CallLink.url(token)
    }

    override fun clear() {
        _calls.value = null
        log = app.orbitle.data.calls.CallHistoryLog()
    }

    companion object {
        /** Звонок журнала 163: собеседник — звонивший или второй участник диалога, у группового — чат. */
        fun item(item: com.max.core.calls.CallHistoryItem, me: Long?, state: MaxState): CallRecord {
            val outgoing = me != null && item.callerId == me
            val chat = state.chats[item.chatId]
            val peerId = when {
                item.groupCallType != null -> null
                !outgoing -> item.callerId.takeIf { it != 0L }
                else -> chat?.let { ChatMapping.dialogPeer(it, me) }
            }
            val peer = peerId?.let { state.users[it] }
            val isGroup = item.groupCallType != null
            val chatId = item.chatId.takeIf { it != 0L }?.toString()
            val title = peerId?.let(state::displayName)?.takeIf { it.isNotBlank() }
                ?: peer?.displayName?.takeIf { it.isNotBlank() }
                ?: item.callName?.takeIf { it.isNotBlank() }
                ?: if (isGroup) "Групповой звонок" else "Звонок"
            return CallRecord(
                id = app.orbitle.data.calls.CallHistoryRecords.id(item),
                peerId = peerId?.toString() ?: chatId ?: item.callId,
                title = title,
                avatarUrl = peer?.baseUrl?.takeIf { it.isNotBlank() },
                isGroup = isGroup,
                chatId = chatId,
                outgoing = outgoing,
                outcome = app.orbitle.data.calls.CallHistoryRecords.outcome(item, outgoing),
                isVideo = item.callType == com.max.core.calls.CallMedia.VIDEO,
                timeMs = item.time,
                durationMs = app.orbitle.data.calls.CallHistoryRecords.duration(item),
            )
        }

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
                title = peerId?.let(state::displayName)?.takeIf { it.isNotBlank() } ?: peer?.displayName?.takeIf { it.isNotBlank() } ?: if (isGroup) "Групповой звонок" else "Звонок",
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
