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
import app.orbitle.domain.ChatSearchResult
import kotlinx.coroutines.CancellationException
import app.orbitle.domain.ChatType
import app.orbitle.domain.FoundMessage
import app.orbitle.presentation.common.ListOrder
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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

/** Страница папки для листания: свои строки и своё пустое состояние. */
data class ChatFolderPage(val id: String, val items: List<ChatListItem>, val content: ChatListContent)

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
    /**
     * Страницы папок в порядке [folders], когда полоса папок видна и поиск закрыт;
     * иначе пусто и экран показывает один список [items].
     */
    val pages: List<ChatFolderPage> = emptyList(),
    /** Найдено на сервере при поиске, без чатов, которые уже есть в списке. */
    val global: List<ChatSearchResult> = emptyList(),
    /** Сообщения по запросу: с сервера и загруженные, новые сверху. */
    val messages: List<FoundMessageItem> = emptyList(),
    /** Запрос к серверу ещё идёт. */
    val isSearchingServer: Boolean = false,
    /** Недавние чаты пустого поиска. Только те, что ещё есть в списке, сначала последний выбранный. */
    val recent: List<ChatListItem> = emptyList(),
    /** Закреплённые можно переставить: папка «Все», поиск закрыт, закреплённых больше одного. */
    val canReorderPins: Boolean = false,
    /** Открыт режим перестановки закреплённых: список показывает только их, с ручками. */
    val isReorderingPins: Boolean = false,
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
    /** Недавние чаты поиска. `null` в тестах, которым список не нужен. */
    private val recents: RecentSearchStore? = null,
    /** Пауза после последней буквы перед запросом к серверу. */
    private val searchDelayMs: Long = SEARCH_DELAY_MS,
) : ViewModel() {

    private var serverSearch: Job? = null
    private var foundMessages: List<FoundMessage> = emptyList()

    private var chats: List<Chat> = emptyList()
    private var hasSnapshot = false
    private var hasRefreshed = false
    private var serverFolders: List<ChatFolder> = emptyList()
    private var typing: Map<String, List<String>> = emptyMap()
    private var connection = ConnectionState.CONNECTING
    private var refreshError: OrbitleError? = null
    private var pendingPins: MutableMap<String, Int?> = mutableMapOf()
    /** Порядок закреплённых после перетаскивания, пока снимок стора его не показал. */
    private var pendingPinOrder: List<String>? = null
    /** Сервер принял [pendingPinOrder]: следующий снимок уже с ним. */
    private var pinOrderAccepted = false
    private var pendingMutes: MutableMap<String, Boolean> = mutableMapOf()
    private var markedUnread: Set<String> = local?.markedUnread.orEmpty()
    private var drafts: Map<String, ChatDraft> = local?.drafts().orEmpty()
    private var recentIds: List<String> = recents?.recent().orEmpty()

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
                    if (pendingPinOrder != null && (pinOrderAccepted || pinnedIds(next) == pendingPinOrder)) {
                        pendingPinOrder = null
                        pinOrderAccepted = false
                    }
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
        scheduleServerSearch()
    }

    fun setSearchQuery(query: String) {
        val changed = query.trim() != _state.value.searchQuery.trim()
        _state.value = _state.value.copy(searchQuery = query)
        rebuild()
        if (changed) scheduleServerSearch()
    }

    /** Чат выбран из поиска: он становится первым в недавних. */
    fun selectSearchResult(chatId: String) {
        val next = RecentSearchList.add(recentIds, chatId)
        if (next == recentIds) return
        recentIds = next
        recents?.add(chatId)
        rebuild()
    }

    fun removeRecent(chatId: String) {
        val next = RecentSearchList.remove(recentIds, chatId)
        if (next == recentIds) return
        recentIds = next
        recents?.remove(chatId)
        rebuild()
    }

    fun clearRecent() {
        if (recentIds.isEmpty()) return
        recentIds = emptyList()
        recents?.clear()
        rebuild()
    }

    /**
     * Поиск на сервере, как в приложении для iOS: после паузы в наборе, от двух букв.
     * Прежний запрос отменяется; ответ на устаревший запрос не показывается, ошибка — просто пусто.
     */
    private suspend fun <T> orEmpty(load: suspend () -> List<T>): List<T> = try {
        load()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        emptyList()
    }

    /** Строки найденных сообщений с названием чата из списка. */
    private fun messageItems(): List<FoundMessageItem> {
        if (foundMessages.isEmpty()) return emptyList()
        val byId = chats.associateBy { it.id }
        val nowMs = now()
        return foundMessages.map { found ->
            val chat = byId[found.chatId]
            val type = chat?.type ?: ChatType.PRIVATE
            val title = when {
                chat == null -> FoundMessageItem.UNKNOWN_CHAT_TITLE
                chat.isSavedMessages -> ChatListFormatter.SAVED_MESSAGES_TITLE
                else -> chat.title
            }
            // Автор — в группах и каналах; в личном чате видно и так, свои — «Вы».
            val author = when {
                found.isOutgoing -> FoundMessageItem.OUTGOING_AUTHOR
                type == ChatType.PRIVATE -> null
                else -> found.senderName
            }
            FoundMessageItem(
                chatId = found.chatId,
                messageId = found.messageId,
                chatTitle = title,
                chatType = type,
                isSavedMessages = chat?.isSavedMessages == true,
                author = author,
                snippet = FoundMessageItem.snippet(found.text),
                time = if (found.timeMs > 0) formatter.timeLabel(found.timeMs, nowMs) else "",
                timeMs = found.timeMs,
            )
        }
    }

    private fun scheduleServerSearch() {
        serverSearch?.cancel()
        serverSearch = null
        val current = _state.value
        val query = current.searchQuery.trim()
        if (!current.isSearchActive || query.length < SERVER_SEARCH_MIN_LENGTH) {
            foundMessages = emptyList()
            if (current.isSearchingServer || current.global.isNotEmpty() || current.messages.isNotEmpty()) {
                _state.value = current.copy(global = emptyList(), messages = emptyList(), isSearchingServer = false)
            }
            return
        }
        _state.value = current.copy(isSearchingServer = true)
        serverSearch = viewModelScope.launch {
            delay(searchDelayMs)
            val (found, messages) = coroutineScope {
                val publicChats = async { orEmpty { repository.searchPublic(query) } }
                val foundMessages = async { orEmpty { repository.searchMessages(query) } }
                publicChats.await() to foundMessages.await()
            }
            if (_state.value.searchQuery.trim() != query || !_state.value.isSearchActive) return@launch
            val known = chats.mapTo(HashSet()) { it.id }
            foundMessages = messages
            _state.value = _state.value.copy(
                global = found.distinctBy { it.id }.filterNot { it.id in known },
                messages = messageItems(),
                isSearchingServer = false,
            )
        }
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

    /** Режим перестановки закреплённых: открывает папку «Все» и закрывает поиск. */
    fun startPinReorder() {
        if (!_state.value.canReorderPins) return
        _state.value = _state.value.copy(
            selectedFolderId = ChatFolder.ALL_ID,
            isSearchActive = false,
            searchQuery = "",
            isReorderingPins = true,
        )
        rebuild()
    }

    fun finishPinReorder() {
        if (!_state.value.isReorderingPins) return
        _state.value = _state.value.copy(isReorderingPins = false)
    }

    /**
     * Новый порядок закреплённых сверху вниз (все закреплённые папки «Все»). Список встаёт в этот
     * порядок сразу; если сервер откажет, возвращается порядок сервера и показывается ошибка.
     */
    fun reorderPinned(order: List<String>) {
        val pinned = pinnedIds(ordered())
        if (order == pinned || !ListOrder.isPermutation(order, pinned)) return
        pendingPinOrder = order
        pinOrderAccepted = false
        rebuild()
        viewModelScope.launch {
            try {
                repository.reorderPinned(order)
                if (pendingPinOrder == order) {
                    // Стор мог прислать новый порядок раньше ответа — тогда держать нечего.
                    if (pinnedIds(chats) == order) pendingPinOrder = null else pinOrderAccepted = true
                    rebuild()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (pendingPinOrder == order) {
                    pendingPinOrder = null
                    pinOrderAccepted = false
                }
                _messages.value = CoreErrors.map(e).userMessage
                rebuild()
            }
        }
    }

    /** Сдвинуть закреплённый чат на [offset] мест (действия «выше» и «ниже» для TalkBack). */
    fun movePinned(chatId: String, offset: Int) {
        val pinned = pinnedIds(ordered())
        val from = pinned.indexOf(chatId)
        if (from < 0) return
        reorderPinned(ListOrder.moved(pinned, from, from + offset))
    }

    /** Экран снова виден: черновики, пометки и недавний поиск могли поменяться. */
    fun reloadLocal() {
        val store = local
        if (store != null) {
            markedUnread = store.markedUnread
            drafts = store.drafts()
        }
        val fresh = recents?.recent()
        if (fresh != null) recentIds = fresh
        if (store != null || fresh != null) rebuild()
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

    /** Удалить чат: `forEveryone` — у всех, иначе только у себя. */
    fun deleteChat(chatId: String, forEveryone: Boolean) {
        viewModelScope.launch {
            try {
                repository.deleteChat(chatId, forEveryone)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _messages.value = CoreErrors.map(e).userMessage
            }
        }
    }

    /** Очистить переписку. Чат остаётся в списке. */
    fun clearHistory(chatId: String, forEveryone: Boolean) {
        viewModelScope.launch {
            try {
                repository.clearHistory(chatId, forEveryone)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _messages.value = CoreErrors.map(e).userMessage
            }
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

    /** Чат есть в списке аккаунта: участник группы или подписчик канала. */
    fun isListed(chatId: String): Boolean = ordered().any { it.id == chatId }

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

    /** Закреплённые папки «Все» сверху вниз. */
    private fun pinnedIds(list: List<Chat>): List<String> =
        list.filter { it.isPinned && ChatFolder.all.contains(it) }.sortedWith(Chat.listOrder).map { it.id }

    private fun ordered(): List<Chat> {
        val pinPlaces = pendingPinOrder?.withIndex()?.associate { (index, id) -> id to index }
        return chats.map { chat -> withPending(chat, pinPlaces) }.sortedWith(Chat.listOrder)
    }

    private fun withPending(chat: Chat, pinPlaces: Map<String, Int>?): Chat {
        var next = chat
        if (pendingPins.containsKey(chat.id)) next = next.copy(pinOrder = pendingPins[chat.id])
        // Порядок после перетаскивания. Закреплённый позже остаётся сверху (`-1`), откреплённый не возвращается.
        if (next.isPinned) pinPlaces?.get(chat.id)?.let { next = next.copy(pinOrder = it) }
        pendingMutes[chat.id]?.let { next = next.copy(isMuted = it) }
        if (chat.id in markedUnread && chat.unreadCount == 0) next = next.copy(isMarkedUnread = true)
        drafts[chat.id]?.let { next = next.copy(draft = it) }
        return next
    }

    private fun rebuild() {
        val current = _state.value
        val sorted = ordered()
        val definitions = listOf(ChatFolder.all) + serverFolders
        val tabs = definitions.map { folder ->
            ChatFolderTab(folder.id, folder.title, sorted.count { folder.contains(it) && it.isUnread && !it.isMuted })
        }
        val selected = if (tabs.any { it.id == current.selectedFolderId }) current.selectedFolderId else ChatFolder.ALL_ID
        val folder = definitions.firstOrNull { it.id == selected } ?: ChatFolder.all
        val canReorderPins = selected == ChatFolder.ALL_ID && !current.isSearchActive && pinnedIds(sorted).size > 1
        val query = current.searchQuery.trim().lowercase()
        val nowMs = now()
        // Строка чата форматируется один раз, даже если чат входит в несколько папок.
        val formatted = HashMap<String, ChatListItem>()
        fun itemOf(chat: Chat) = formatted.getOrPut(chat.id) { formatter.item(chat, nowMs, typing[chat.id].orEmpty()) }
        val pages = if (tabs.size > 1 && !current.isSearchActive) {
            definitions.map { f ->
                val rows = sorted.filter { f.contains(it) }.map(::itemOf)
                ChatFolderPage(f.id, rows, contentFor(rows, query = ""))
            }
        } else {
            emptyList()
        }
        val items = (pages.firstOrNull { it.id == selected }?.items ?: sorted.filter { folder.contains(it) }.map(::itemOf))
            .filter { query.isEmpty() || it.title.lowercase().contains(query) }
        val content = contentFor(items, query)
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
            pages = pages,
            // Чат мог появиться в списке, пока шёл поиск: тогда он среди своих, а не найденных.
            global = if (current.global.isEmpty()) current.global else current.global.filterNot { g -> chats.any { it.id == g.id } },
            messages = if (current.messages.isEmpty()) current.messages else messageItems(),
            recent = if (current.isSearchActive && query.isEmpty()) {
                recentIds.mapNotNull { id -> sorted.firstOrNull { it.id == id }?.let(::itemOf) }
            } else {
                emptyList()
            },
            canReorderPins = canReorderPins,
            // Закреплённых осталось меньше двух (открепили на другом устройстве) — режим закрывается.
            isReorderingPins = current.isReorderingPins && canReorderPins,
        )
    }

    private fun contentFor(items: List<ChatListItem>, query: String): ChatListContent = when {
        items.isNotEmpty() -> ChatListContent.List
        query.isNotEmpty() && hasSnapshot -> ChatListContent.Empty
        !hasSnapshot && refreshError == null && connection != ConnectionState.OFFLINE -> ChatListContent.Loading
        !hasSnapshot && connection == ConnectionState.OFFLINE -> ChatListContent.Offline
        !hasSnapshot && refreshError != null -> ChatListContent.Failed(refreshError?.userMessage ?: "Не удалось загрузить чаты")
        else -> ChatListContent.Empty
    }

    companion object {
        /** Сколько чатов можно закрепить. Сервер может отказать и раньше. */
        const val DEFAULT_PIN_LIMIT = 10
        const val SEARCH_DELAY_MS = 300L
        /** Короче запрос сервер не ищет. */
        const val SERVER_SEARCH_MIN_LENGTH = 2
    }
}

/** Строка найденного сообщения: чат, автор, кусок текста и время. */
data class FoundMessageItem(
    val chatId: String,
    val messageId: String,
    val chatTitle: String,
    val chatType: ChatType,
    val isSavedMessages: Boolean,
    /** «Вы», имя автора в группе или `null`. */
    val author: String?,
    val snippet: String,
    val time: String,
    /** Время сообщения, мс Unix; 0 — неизвестно. Чат открывается на нём без лишнего запроса. */
    val timeMs: Long = 0,
) {
    companion object {
        const val OUTGOING_AUTHOR = "Вы"
        const val UNKNOWN_CHAT_TITLE = "Чат"
        private const val SNIPPET_LENGTH = 160

        /** Текст одной строкой и не длиннее строки списка. */
        fun snippet(text: String): String {
            val line = text.trim().replace(Regex("\\s+"), " ")
            return if (line.length > SNIPPET_LENGTH) line.take(SNIPPET_LENGTH).trimEnd() + "…" else line
        }
    }
}
