package app.orbitle.data

import app.orbitle.domain.Chat
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

    override fun clear() {
        loaded.value = false
        usersRequested = mutableSetOf()
    }

    private companion object {
        const val TYPING_TICK_MS = 1_000L
    }
}
