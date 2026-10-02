package app.orbitle.data

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatSearchResult
import app.orbitle.domain.ChatType
import app.orbitle.domain.FoundMessage
import com.max.core.api.MaxMessage
import com.max.core.api.PublicSearchHit
import com.max.core.state.MaxState
import kotlinx.coroutines.CancellationException
import app.orbitle.domain.ServerFolder
import com.max.shared.MaxClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** [ChatRepository] над стором `MaxClient`. */
class CoreChatRepository(
    private val client: MaxClient,
    private val clock: () -> Long = System::currentTimeMillis,
) : ChatRepository {

    /** Снимок уже пришёл: до него список показывает загрузку, а не «Нет чатов». */
    private val loaded = MutableStateFlow(false)
    private val refreshLock = Mutex()
    private var usersRequested = mutableSetOf<Long>()

    override val chats: Flow<List<Chat>?> =
        combine(client.store.state, client.accountConfig, loaded) { state, config, ready ->
            if (!ready && state.chats.isEmpty()) null else ChatMapping.chats(state, config, clock())
        }.distinctUntilChanged()

    override val folders: Flow<List<ServerFolder>> = client.store.state
        .map { it.chatFolders }
        .distinctUntilChanged()
        .map { folders -> ChatMapping.folders(folders).filterNot { it.isAllChats } }

    private val ticks: Flow<Long> = flow {
        while (true) {
            emit(clock())
            delay(TYPING_TICK_MS)
        }
    }

    override val typing: Flow<Map<String, List<String>>> = combine(client.store.state, ticks) { state, now ->
        state.typing.keys.mapNotNull { chatId ->
            val users = state.typingUsers(chatId, now).filter { it != state.me }
            if (users.isEmpty()) null else chatId.toString() to users.map { it.toString() }
        }.toMap()
    }.distinctUntilChanged()

    override suspend fun refresh() {
        if (refreshLock.isLocked) return
        refreshLock.withLock {
            MaxCoreGateway.call {
                if (client.store.state.value.chats.isEmpty()) client.loadAllChats() else client.loadChats()
            }
            runCatching { MaxCoreGateway.call { client.loadFolders() } }
            loaded.value = true
            resolveUsers()
        }
    }

    /** Собеседники и авторы последних сообщений, которых ещё нет в сторе, порциями по 100. */
    private suspend fun resolveUsers() {
        val state = client.store.state.value
        val wanted = buildSet {
            for (chat in state.chats.values) {
                ChatMapping.dialogPeer(chat, state.me)?.let(::add)
                chat.lastMessage?.sender?.let(::add)
            }
        }.filter { it !in state.users && it !in usersRequested }
        if (wanted.isEmpty()) return
        usersRequested.addAll(wanted)
        for (chunk in wanted.chunked(100)) {
            runCatching { MaxCoreGateway.call { client.loadUsers(chunk) } }
        }
    }

    override suspend fun setPinned(chatId: String, pinned: Boolean) {
        val id = chatId.toLongOrNull() ?: return
        val current = client.store.state.value.pinnedChatIds.orEmpty()
        val next = if (pinned) listOf(id) + current.filter { it != id } else current.filter { it != id }
        MaxCoreGateway.call { client.setPinnedChats(next) }
    }

    override suspend fun setMuted(chatId: String, muted: Boolean) {
        val id = chatId.toLongOrNull() ?: return
        MaxCoreGateway.call { client.setChatMuted(id, muted) }
    }

    override suspend fun searchPublic(query: String): List<ChatSearchResult> {
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        val hits = MaxCoreGateway.call { client.api.search.searchPublic(term, 0, SEARCH_PAGE_SIZE) }
        return hits.mapNotNull(::searchResultOf)
    }

    override suspend fun searchMessages(query: String): List<FoundMessage> {
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        // Без ответа сервера остаются совпадения среди загруженных сообщений.
        val hits = try {
            MaxCoreGateway.call { client.api.search.searchMessages(term, MESSAGE_SEARCH_COUNT) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            emptyList()
        }
        return foundMessages(term, hits.map { it.chatId to it.message }, client.store.state.value)
    }

    override suspend fun markAsRead(chatId: String) {
        val id = chatId.toLongOrNull() ?: return
        val state = client.store.state.value
        val last = state.chats[id]?.lastMessage?.id ?: state.messagesOf(id).maxByOrNull { it.time }?.id ?: return
        val read = MaxCoreGateway.call { client.api.messages.markRead(id, last) }
        val me = state.me ?: return
        client.store.apply(com.max.core.events.MaxEvent.MessageRead(id, me, read.mark, false, 0, null))
    }

    override fun clear() {
        loaded.value = false
        usersRequested = mutableSetOf()
    }

    companion object {
        private const val TYPING_TICK_MS = 1_000L

        /** Сколько публичных чатов просить за раз. */
        const val SEARCH_PAGE_SIZE = 20

        /** Сколько найденных сообщений просить у сервера. */
        const val MESSAGE_SEARCH_COUNT = 50

        /**
         * Найденное сервером вместе с совпадениями среди загруженных сообщений: без повторов
         * (у загруженной копии точное время), без пустых и без чата 0, новые сверху.
         */
        fun foundMessages(query: String, server: List<Pair<Long, MaxMessage>>, state: MaxState): List<FoundMessage> {
            val term = query.trim()
            if (term.isEmpty()) return emptyList()
            val local = state.messages.flatMap { (chatId, list) ->
                list.filter { it.text.contains(term, ignoreCase = true) }.map { chatId to it }
            }
            return (local + server)
                .filter { (chatId, message) -> chatId != 0L && message.text.isNotBlank() }
                .distinctBy { (chatId, message) -> chatId to message.id }
                .sortedByDescending { (_, message) -> message.time }
                .map { (chatId, message) ->
                    val sender = message.sender
                    FoundMessage(
                        chatId = chatId.toString(),
                        messageId = message.id.toString(),
                        senderName = sender?.let { state.users[it]?.displayName }?.takeIf { it.isNotBlank() },
                        isOutgoing = sender != null && sender == state.me,
                        text = message.text.trim(),
                        timeMs = message.time,
                    )
                }
        }

        /**
         * Найденный чат или канал. Люди пропускаются: у найденного человека ещё нет чата,
         * который можно открыть. Без названия — по типу: «Канал», «Группа» или «Чат».
         */
        fun searchResultOf(hit: PublicSearchHit): ChatSearchResult? {
            val chat = hit.chat ?: return null
            val type = ChatType.fromCore(chat.type)
            val title = chat.title?.trim().orEmpty().ifEmpty {
                when (type) {
                    ChatType.CHANNEL -> "Канал"
                    ChatType.GROUP -> "Группа"
                    else -> "Чат"
                }
            }
            val subtitle = hit.link?.let { "@$it" } ?: chat.lastMessage?.text?.trim()?.takeIf { it.isNotEmpty() }
            return ChatSearchResult(chat.id.toString(), title, subtitle, type, hit.iconUrl)
        }
    }
}
