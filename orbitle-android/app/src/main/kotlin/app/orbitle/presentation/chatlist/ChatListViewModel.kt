package app.orbitle.presentation.chatlist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.orbitle.data.ChatRepository
import app.orbitle.data.CoreErrors
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.ChatFolder
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch

/** Что список хранит на устройстве: ручные пометки «непрочитано» и черновики. */
interface ChatLocalMarks {
    var markedUnread: Set<String>
    fun drafts(): Map<String, ChatDraft>
}

/** Папка в полосе над списком с числом непрочитанных чатов. */
data class ChatFolderTab(val id: String, val title: String, val unreadCount: Int) {
    val badge: String? get() = ChatListFormatter.badge(unreadCount)
}

/** Что показать вместо списка, когда строк нет. */
sealed interface ChatListContent {
    data object Loading : ChatListContent
    data object List : ChatListContent
    data object Empty : ChatListContent
    data object Offline : ChatListContent
    data class Failed(val message: String) : ChatListContent
}

data class ChatListUiState(
    val items: List<ChatListItem> = emptyList(),
    val folders: List<ChatFolderTab> = emptyList(),
    val selectedFolderId: String = ChatFolder.ALL_ID,
    val content: ChatListContent = ChatListContent.Loading,
    /** Плашка над списком: «Подключение…», «Нет сети». `null` — всё хорошо. */
    val banner: String? = null,
    val isRefreshing: Boolean = false,
    val searchQuery: String = "",
    val isSearchActive: Boolean = false,
    /** Бейдж вкладки «Чаты»: число непрочитанных чатов со звуком. */
    val tabBadge: Int = 0,
    val error: String? = null,
) {
    /** Полоса папок видна, только если у пользователя есть папки кроме «Все». */
    val showsFolders: Boolean get() = folders.size > 1
}

/** Список чатов: живой поток из репозитория, папки, поиск, закреплённые и соединение. */
class ChatListViewModel(
    private val repository: ChatRepository,
    connection: Flow<ConnectionState> = flowOf(ConnectionState.ONLINE),
    private val formatter: ChatListFormatter = ChatListFormatter(),
    private val now: () -> Long = System::currentTimeMillis,
    private val pinLimit: Int = DEFAULT_PIN_LIMIT,
    /** Пометки и черновики на устройстве. */
    private val local: ChatLocalMarks? = null,
) : ViewModel() {

    private var chats: List<Chat> = emptyList()
    private var hasSnapshot = false
    private var hasRefreshed = false
    private var serverFolders: List<ChatFolder> = emptyList()
    private var typing: Map<String, List<String>> = emptyMap()
    private var connection = ConnectionState.CONNECTING
    private var refreshError: OrbitleError? = null
    private var pendingPins: MutableMap<String, Int?> = mutableMapOf()
    private var pendingMutes: MutableMap<String, Boolean> = mutableMapOf()
    private var markedUnread: Set<String> = local?.markedUnread.orEmpty()
    private var drafts: Map<String, ChatDraft> = local?.drafts().orEmpty()

    private val _state = MutableStateFlow(ChatListUiState())
    val state: StateFlow<ChatListUiState> = _state.asStateFlow()

    /** Ошибки действий для снекбара. */
    private val _messages = MutableStateFlow<String?>(null)
    val messages: StateFlow<String?> = _messages.asStateFlow()

    init {
        viewModelScope.launch {
            repository.chats.collect { next ->
                if (next != null) {
                    hasSnapshot = true
                    chats = next
                    pendingPins.entries.removeAll { (id, order) -> next.firstOrNull { it.id == id }?.let { (it.pinOrder == null) == (order == null) } ?: true }
                    pendingMutes.entries.removeAll { (id, muted) -> next.firstOrNull { it.id == id }?.let { it.isMuted == muted } ?: true }
                }
                rebuild()
            }
        }
        viewModelScope.launch {
            repository.folders.collect { list ->
                serverFolders = list.map { it.chatFolder }
                rebuild()
            }
        }
        viewModelScope.launch {
            repository.typing.collect {
                typing = it
                rebuild()
            }
        }
        viewModelScope.launch {
            connection.collect {
                val wasOffline = this@ChatListViewModel.connection != ConnectionState.ONLINE
                this@ChatListViewModel.connection = it
                rebuild()
                if (it == ConnectionState.ONLINE && wasOffline && hasRefreshed) refresh()
            }
        }
        // Время в строках («сегодня» → «вчера») обновляется раз в минуту.
        viewModelScope.launch {
            while (true) {
                delay(60_000)
                rebuild()
            }
        }
    }

    fun refresh() {
        if (_state.value.isRefreshing) return
        _state.value = _state.value.copy(isRefreshing = true)
        viewModelScope.launch {
            refreshError = try {
                repository.refresh()
                null
            } catch (e: Throwable) {
                CoreErrors.map(e).takeIf { it != OrbitleError.Cancelled }
            }
            hasRefreshed = true
            _state.value = _state.value.copy(isRefreshing = false)
            rebuild()
        }
    }

    fun selectFolder(id: String) {
        if (id == _state.value.selectedFolderId) return
        _state.value = _state.value.copy(selectedFolderId = id)
        rebuild()
    }

    fun setSearchActive(active: Boolean) {
        _state.value = _state.value.copy(isSearchActive = active, searchQuery = if (active) _state.value.searchQuery else "")
        rebuild()
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        rebuild()
    }

    fun togglePin(chatId: String) {
        val chat = chats.firstOrNull { it.id == chatId } ?: return
        val pinnedNow = if (pendingPins.containsKey(chatId)) pendingPins[chatId] != null else chat.isPinned
        val pin = !pinnedNow
        if (pin && chats.count { it.isPinned } >= pinLimit) {
            _messages.value = "Можно закрепить не больше $pinLimit чатов"
            return
        }
        pendingPins[chatId] = if (pin) -1 else null
        rebuild()
        viewModelScope.launch {
            try {
                repository.setPinned(chatId, pin)
            } catch (e: Throwable) {
                pendingPins.remove(chatId)
                _messages.value = CoreErrors.map(e).userMessage
                rebuild()
            }
        }
    }

    /** Экран снова виден: черновики и пометки могли поменяться в чате. */
    fun reloadLocal() {
        val store = local ?: return
        markedUnread = store.markedUnread
        drafts = store.drafts()
        rebuild()
    }

    /** Чат открыт: ручная пометка «непрочитано» снимается. */
    fun opened(chatId: String) {
        if (chatId !in markedUnread) return
        markedUnread = markedUnread - chatId
        local?.markedUnread = markedUnread
        rebuild()
    }

    /** Непрочитанный — прочитать на сервере; прочитанный — пометить непрочитанным на устройстве. */
    fun toggleRead(chatId: String) {
        val chat = chats.firstOrNull { it.id == chatId } ?: return
        if (chat.unreadCount > 0 || chatId in markedUnread) {
            markedUnread = markedUnread - chatId
            local?.markedUnread = markedUnread
            rebuild()
            if (chat.unreadCount > 0) viewModelScope.launch {
                try {
                    repository.markAsRead(chatId)
                } catch (e: Throwable) {
                    _messages.value = CoreErrors.map(e).userMessage
                }
            }
        } else {
            markedUnread = markedUnread + chatId
            local?.markedUnread = markedUnread
            rebuild()
        }
    }

    fun toggleMute(chatId: String) {
        val chat = chats.firstOrNull { it.id == chatId } ?: return
        val previous = pendingMutes[chatId]
        val mutedNow = previous ?: chat.isMuted
        pendingMutes[chatId] = !mutedNow
        rebuild()
        viewModelScope.launch {
            try {
                repository.setMuted(chatId, !mutedNow)
            } catch (e: Throwable) {
                if (previous == null) pendingMutes.remove(chatId) else pendingMutes[chatId] = previous
                _messages.value = CoreErrors.map(e).userMessage
                rebuild()
            }
        }
    }

    fun consumeMessage() {
        _messages.value = null
    }

    /** Куда можно переслать сообщение: чаты вне архива в порядке списка, кроме [excluding]. */
    fun forwardTargets(excluding: String? = null): List<ChatListItem> {
        val at = now()
        return ordered().filter { !it.isArchived && it.id != excluding && it.canWrite != false }
            .map { formatter.item(it, at, showDraft = false) }
    }

    /** Чаты для папки: всё, кроме архива, в порядке списка. */
    fun folderCandidates(): List<ChatListItem> {
        val at = now()
        return ordered().filter { !it.isArchived }.map { formatter.item(it, at, showDraft = false) }
    }

    /** Сколько чатов попадает в серверную папку; для «Все» — все чаты вне архива. */
    fun folderCount(folder: app.orbitle.domain.ServerFolder): Int {
        val rule = if (folder.isAllChats) app.orbitle.domain.ChatFolder.all else folder.chatFolder
        return ordered().count(rule::contains)
    }

    private fun ordered(): List<Chat> = chats.map { chat ->
        var next = chat
        if (pendingPins.containsKey(chat.id)) next = next.copy(pinOrder = pendingPins[chat.id])
        pendingMutes[chat.id]?.let { next = next.copy(isMuted = it) }
        if (chat.id in markedUnread && chat.unreadCount == 0) next = next.copy(isMarkedUnread = true)
        drafts[chat.id]?.let { next = next.copy(draft = it) }
        next
    }.sortedWith(Chat.listOrder)

    private fun rebuild() {
        val current = _state.value
        val sorted = ordered()
        val definitions = listOf(ChatFolder.all) + serverFolders
        val tabs = definitions.map { folder ->
            ChatFolderTab(folder.id, folder.title, sorted.count { folder.contains(it) && it.isUnread && !it.isMuted })
        }
        val selected = if (tabs.any { it.id == current.selectedFolderId }) current.selectedFolderId else ChatFolder.ALL_ID
        val folder = definitions.firstOrNull { it.id == selected } ?: ChatFolder.all
        val query = current.searchQuery.trim().lowercase()
        val nowMs = now()
        val visible = sorted.filter { folder.contains(it) }
        val items = visible.map { formatter.item(it, nowMs, typing[it.id].orEmpty()) }
            .filter { query.isEmpty() || it.title.lowercase().contains(query) }
        val content = when {
            items.isNotEmpty() -> ChatListContent.List
            query.isNotEmpty() && hasSnapshot -> ChatListContent.Empty
            !hasSnapshot && refreshError == null && connection != ConnectionState.OFFLINE -> ChatListContent.Loading
            !hasSnapshot && connection == ConnectionState.OFFLINE -> ChatListContent.Offline
            !hasSnapshot && refreshError != null -> ChatListContent.Failed(refreshError?.userMessage ?: "Не удалось загрузить чаты")
            else -> ChatListContent.Empty
        }
        val banner = when (connection) {
            ConnectionState.ONLINE -> null
            ConnectionState.CONNECTING -> "Подключение…"
            ConnectionState.OFFLINE -> "Нет соединения"
        }
        _state.value = current.copy(
            items = items,
            folders = tabs,
            selectedFolderId = selected,
            content = content,
            banner = banner,
            tabBadge = sorted.count { it.isUnread && !it.isMuted && !it.isArchived },
            error = refreshError?.userMessage?.takeIf { hasSnapshot },
        )
    }

    companion object {
        /** Сколько чатов можно закрепить. Сервер может отказать и раньше. */
        const val DEFAULT_PIN_LIMIT = 10
    }
}
