package app.maxly.presentation

import app.maxly.MainDispatcherRule
import app.maxly.data.ChatRepository
import app.maxly.data.CoreFailure
import app.maxly.domain.Chat
import app.maxly.domain.ChatDraft
import app.maxly.presentation.chat.FakeDraftServer
import app.maxly.domain.ChatSearchResult
import app.maxly.domain.FoundMessage
import app.maxly.presentation.chatlist.FoundMessageItem
import app.maxly.domain.ChatType
import app.maxly.domain.ConnectionState
import app.maxly.domain.SessionRejection
import app.maxly.presentation.auth.LoginNotice
import app.maxly.domain.ServerFolder
import app.maxly.presentation.chatlist.ChatListContent
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.data.PreferenceStore
import app.maxly.presentation.chatlist.ChatListViewModel
import app.maxly.presentation.chatlist.ChatLocalMarks
import app.maxly.presentation.chatlist.PreferenceRecentSearches
import app.maxly.presentation.chatlist.RecentSearchList
import app.maxly.presentation.chatlist.RecentSearchStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class FakeChats : ChatRepository {
    override val chats = MutableStateFlow<List<Chat>?>(null)
    override val folders = MutableStateFlow<List<ServerFolder>>(emptyList())
    override val typing = MutableStateFlow<Map<String, List<app.maxly.domain.Typist>>>(emptyMap())
    var refreshFailure: Throwable? = null
    var pinFailure: Throwable? = null
    val pins = mutableListOf<Pair<String, Boolean>>()

    override suspend fun refresh() {
        refreshFailure?.let { throw it }
    }

    override suspend fun setPinned(chatId: String, pinned: Boolean) {
        pins += chatId to pinned
        pinFailure?.let { throw it }
        chats.value = chats.value?.map { if (it.id == chatId) it.copy(pinOrder = if (pinned) 0 else null) else it }
    }

    val reorders = mutableListOf<List<String>>()
    var reorderFailure: Throwable? = null
    /** Пока не завершён, ответ сервера на перестановку не пришёл. */
    var reorderGate: CompletableDeferred<Unit>? = null

    /** Как ядро: стор меняется только после ответа сервера. */
    override suspend fun reorderPinned(chatIds: List<String>) {
        reorders += chatIds
        reorderGate?.await()
        reorderFailure?.let { throw it }
        chats.value = chats.value?.map { chat -> chatIds.indexOf(chat.id).takeIf { it >= 0 }?.let { chat.copy(pinOrder = it) } ?: chat }
    }

    val mutes = mutableListOf<Pair<String, Boolean>>()
    val reads = mutableListOf<String>()
    var muteFailure: Throwable? = null

    override suspend fun setMuted(chatId: String, muted: Boolean) {
        mutes += chatId to muted
        muteFailure?.let { throw it }
    }

    override suspend fun markAsRead(chatId: String) {
        reads += chatId
    }

    val searches = mutableListOf<String>()
    var searchResult: List<ChatSearchResult> = emptyList()
    var searchFailure: Throwable? = null

    override suspend fun searchPublic(query: String): List<ChatSearchResult> {
        searches += query
        searchFailure?.let { throw it }
        return searchResult
    }

    val messageSearches = mutableListOf<String>()
    var messageResult: List<FoundMessage> = emptyList()
    var messageFailure: Throwable? = null

    override suspend fun searchMessages(query: String): List<FoundMessage> {
        messageSearches += query
        messageFailure?.let { throw it }
        return messageResult
    }

    override fun clear() = Unit
}

class FakeMarks : ChatLocalMarks {
    override var markedUnread: Set<String> = emptySet()
    var stored: Map<String, ChatDraft> = emptyMap()
    override fun drafts(): Map<String, ChatDraft> = stored
}

class ChatListViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val repo = FakeChats()
    private val connection = MutableStateFlow(ConnectionState.ONLINE)
    private val now = 1_790_683_200_000L
    private val marks = FakeMarks()
    private val vm by lazy { ChatListViewModel(repo, connection, ChatListFormatter(ZoneOffset.UTC), now = { now }, local = marks) }

    private fun chat(id: String, type: ChatType = ChatType.PRIVATE, at: Long = now, unread: Int = 0, pin: Int? = null, muted: Boolean = false) =
        Chat(id = id, title = "Чат $id", type = type, lastMessageId = "1", unreadCount = unread, updatedAtMs = at, preview = "текст", pinOrder = pin, isMuted = muted)

    @Test
    fun loadingUntilFirstSnapshot() {
        assertEquals(ChatListContent.Loading, vm.state.value.content)
        repo.chats.value = emptyList()
        assertEquals(ChatListContent.Empty, vm.state.value.content)
    }

    @Test
    fun offlineWithoutSnapshot() {
        connection.value = ConnectionState.OFFLINE
        assertEquals(ChatListContent.Offline, vm.state.value.content)
        assertEquals("Нет соединения", vm.state.value.banner)
        connection.value = ConnectionState.CONNECTING
        assertEquals("Подключение…", vm.state.value.banner)
    }

    @Test
    fun floodShowsABannerOverTheSavedList() {
        val throttled = MutableStateFlow<SessionRejection?>(null)
        val vm = ChatListViewModel(repo, connection, ChatListFormatter(ZoneOffset.UTC), now = { now }, local = marks, throttled = throttled)
        repo.chats.value = listOf(chat("a"))
        assertNull(vm.state.value.loginNotice)
        connection.value = ConnectionState.OFFLINE
        throttled.value = SessionRejection(SessionRejection.Reason.FLOOD, title = "Подождите", localizedMessage = "Вход через 5 минут")
        // Список из сохранённого остаётся, сверху текст сервера.
        assertEquals(listOf("a"), vm.state.value.items.map { it.id })
        assertEquals(ChatListContent.List, vm.state.value.content)
        assertEquals(LoginNotice("Подождите", "Вход через 5 минут", LoginNotice.Placement.CHAT_LIST_BANNER), vm.state.value.loginNotice)
        // Без текста сервера — свой.
        throttled.value = SessionRejection(SessionRejection.Reason.FLOOD)
        assertEquals("Слишком много входов", vm.state.value.loginNotice?.title)
        // Снова подключились — баннера нет.
        throttled.value = null
        connection.value = ConnectionState.ONLINE
        assertNull(vm.state.value.loginNotice)
    }

    @Test
    fun clearedTokenIsNeverAChatListBanner() {
        val throttled = MutableStateFlow<SessionRejection?>(SessionRejection(SessionRejection.Reason.BLOCKED))
        val vm = ChatListViewModel(repo, connection, ChatListFormatter(ZoneOffset.UTC), now = { now }, local = marks, throttled = throttled)
        assertNull(vm.state.value.loginNotice)
    }

    @Test
    fun failedRefreshWithoutSnapshot() {
        repo.refreshFailure = CoreFailure("SERVER", "boom")
        vm.refresh()
        assertEquals(ChatListContent.Failed("Ошибка сервера (boom). Попробуйте позже"), vm.state.value.content)
    }

    @Test
    fun ordersPinsFirstAndCountsBadge() {
        repo.chats.value = listOf(chat("a", at = now - 10), chat("b", pin = 0), chat("c", unread = 2), chat("d", unread = 5, muted = true))
        assertEquals(listOf("b", "c", "d", "a"), vm.state.value.items.map { it.id })
        assertEquals(1, vm.state.value.tabBadge)
    }

    @Test
    fun foldersBarOnlyWithServerFolders() {
        repo.chats.value = listOf(chat("1"), chat("2", ChatType.CHANNEL, unread = 1))
        assertFalse(vm.state.value.showsFolders)
        repo.folders.value = listOf(ServerFolder("f", "Каналы", filters = listOf("CHANNEL")))
        assertTrue(vm.state.value.showsFolders)
        assertEquals(listOf("Все", "Каналы"), vm.state.value.folders.map { it.title })
        assertEquals("1", vm.state.value.folders[1].badge)
        vm.selectFolder("f")
        assertEquals(listOf("2"), vm.state.value.items.map { it.id })
        repo.folders.value = emptyList()
        assertEquals("all", vm.state.value.selectedFolderId)
    }

    @Test
    fun pagesHoldEveryFolder() {
        repo.chats.value = listOf(chat("1"), chat("2", ChatType.CHANNEL, unread = 1), chat("3", ChatType.CHANNEL, at = now - 5))
        assertTrue(vm.state.value.pages.isEmpty())
        repo.folders.value = listOf(
            ServerFolder("f", "Каналы", filters = listOf("CHANNEL")),
            ServerFolder("e", "Пусто", chatIds = listOf("nope")),
        )
        val pages = vm.state.value.pages
        assertEquals(listOf("all", "f", "e"), pages.map { it.id })
        assertEquals(listOf("1", "2", "3"), pages[0].items.map { it.id })
        assertEquals(listOf("2", "3"), pages[1].items.map { it.id })
        assertEquals(ChatListContent.List, pages[1].content)
        assertTrue(pages[2].items.isEmpty())
        assertEquals(ChatListContent.Empty, pages[2].content)
        // Строка выбранной папки — та же, что и на её странице.
        vm.selectFolder("f")
        assertEquals(vm.state.value.pages[1].items, vm.state.value.items)
    }

    @Test
    fun selectedFolderSurvivesReorderAndFallsBackWhenRemoved() {
        repo.chats.value = listOf(chat("1"), chat("2", ChatType.CHANNEL))
        val channels = ServerFolder("f", "Каналы", filters = listOf("CHANNEL"))
        val other = ServerFolder("g", "Личные", filters = listOf("DIALOG"))
        repo.folders.value = listOf(channels, other)
        vm.selectFolder("f")
        repo.folders.value = listOf(other, channels)
        assertEquals("f", vm.state.value.selectedFolderId)
        assertEquals(listOf("all", "g", "f"), vm.state.value.pages.map { it.id })
        repo.folders.value = listOf(other)
        assertEquals("all", vm.state.value.selectedFolderId)
        assertEquals(listOf("all", "g"), vm.state.value.pages.map { it.id })
    }

    @Test
    fun noPagesWhileSearching() {
        repo.chats.value = listOf(chat("1"), chat("2", ChatType.CHANNEL))
        repo.folders.value = listOf(ServerFolder("f", "Каналы", filters = listOf("CHANNEL")))
        vm.setSearchActive(true)
        assertTrue(vm.state.value.pages.isEmpty())
        vm.setSearchQuery("2")
        assertEquals(listOf("2"), vm.state.value.items.map { it.id })
        vm.setSearchActive(false)
        assertEquals(2, vm.state.value.pages.size)
    }

    @Test
    fun searchFiltersByTitle() {
        repo.chats.value = listOf(chat("1"), chat("22"))
        vm.setSearchActive(true)
        vm.setSearchQuery("чат 2")
        assertEquals(listOf("22"), vm.state.value.items.map { it.id })
        vm.setSearchQuery("нет такого")
        assertEquals(ChatListContent.Empty, vm.state.value.content)
        vm.setSearchActive(false)
        assertEquals(2, vm.state.value.items.size)
    }

    private fun found(id: String) = ChatSearchResult(id, "Канал $id", "@c$id", ChatType.CHANNEL, null)

    @OptIn(ExperimentalCoroutinesApi::class)
    private fun advance(ms: Long) {
        main.dispatcher.scheduler.advanceTimeBy(ms)
        main.dispatcher.scheduler.runCurrent()
    }

    @Test
    fun serverSearchWaitsForPauseAndSendsLastQuery() {
        repo.chats.value = listOf(chat("1"))
        repo.searchResult = listOf(found("50"))
        vm.setSearchActive(true)
        vm.setSearchQuery("но")
        advance(100)
        vm.setSearchQuery("нов")
        assertTrue(vm.state.value.isSearchingServer)
        advance(ChatListViewModel.SEARCH_DELAY_MS - 1)
        assertTrue(repo.searches.isEmpty())
        advance(1)
        assertEquals(listOf("нов"), repo.searches)
        assertEquals(listOf("50"), vm.state.value.global.map { it.id })
        assertFalse(vm.state.value.isSearchingServer)
    }

    @Test
    fun shortQueryDoesNotGoToServer() {
        repo.chats.value = listOf(chat("1"))
        vm.setSearchActive(true)
        vm.setSearchQuery(" н ")
        advance(ChatListViewModel.SEARCH_DELAY_MS * 2)
        assertTrue(repo.searches.isEmpty())
        assertFalse(vm.state.value.isSearchingServer)
    }

    @Test
    fun ownChatsAreNotRepeatedAmongFound() {
        repo.chats.value = listOf(chat("1"), chat("50"))
        repo.searchResult = listOf(found("50"), found("51"), found("51"))
        vm.setSearchActive(true)
        vm.setSearchQuery("канал")
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(listOf("51"), vm.state.value.global.map { it.id })
        // Чат появился в списке после ответа сервера.
        repo.chats.value = listOf(chat("1"), chat("50"), chat("51"))
        assertTrue(vm.state.value.global.isEmpty())
    }

    @Test
    fun serverErrorLeavesOnlyLocalResults() {
        repo.chats.value = listOf(chat("1"))
        repo.searchFailure = CoreFailure("NETWORK", null)
        vm.setSearchActive(true)
        vm.setSearchQuery("чат")
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(listOf("чат"), repo.searches)
        assertTrue(vm.state.value.global.isEmpty())
        assertFalse(vm.state.value.isSearchingServer)
        assertEquals(listOf("1"), vm.state.value.items.map { it.id })
    }

    @Test
    fun closingSearchDropsFoundAndPendingRequest() {
        repo.chats.value = listOf(chat("1"))
        repo.searchResult = listOf(found("50"))
        vm.setSearchActive(true)
        vm.setSearchQuery("канал")
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(1, vm.state.value.global.size)
        vm.setSearchQuery("канал 2")
        vm.setSearchActive(false)
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(listOf("канал"), repo.searches)
        assertTrue(vm.state.value.global.isEmpty())
        assertFalse(vm.state.value.isSearchingServer)
    }

    private fun foundMessage(chat: String, id: String, text: String = "привет", outgoing: Boolean = false, at: Long = now) =
        FoundMessage(chat, id, senderName = "Анна", isOutgoing = outgoing, text = text, timeMs = at)

    @Test
    fun foundMessagesTakeChatTitleAuthorAndTime() {
        repo.chats.value = listOf(chat("1"), chat("2", ChatType.GROUP), chat("3", ChatType.GROUP))
        repo.messageResult = listOf(
            foundMessage("1", "10", text = "привет\n  как дела"),
            foundMessage("2", "11"),
            foundMessage("3", "12", outgoing = true, at = 0),
            foundMessage("99", "13"),
        )
        vm.setSearchActive(true)
        vm.setSearchQuery("привет")
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(listOf("привет"), repo.messageSearches)
        val rows = vm.state.value.messages
        assertEquals(listOf("10", "11", "12", "13"), rows.map { it.messageId })
        assertEquals("Чат 1", rows[0].chatTitle)
        // В личном чате автор не нужен, в группе — имя, свои — «Вы».
        assertNull(rows[0].author)
        assertEquals("привет как дела", rows[0].snippet)
        assertEquals("Анна", rows[1].author)
        assertEquals(FoundMessageItem.OUTGOING_AUTHOR, rows[2].author)
        assertEquals("", rows[2].time)
        assertTrue(rows[1].time.isNotEmpty())
        assertEquals(FoundMessageItem.UNKNOWN_CHAT_TITLE, rows[3].chatTitle)
    }

    @Test
    fun messageSearchFailureKeepsFoundChats() {
        repo.chats.value = listOf(chat("1"))
        repo.searchResult = listOf(found("50"))
        repo.messageFailure = CoreFailure("NETWORK", null)
        vm.setSearchActive(true)
        vm.setSearchQuery("канал")
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(listOf("50"), vm.state.value.global.map { it.id })
        assertTrue(vm.state.value.messages.isEmpty())
        assertFalse(vm.state.value.isSearchingServer)
    }

    @Test
    fun closingSearchDropsFoundMessages() {
        repo.chats.value = listOf(chat("1"))
        repo.messageResult = listOf(foundMessage("1", "10"))
        vm.setSearchActive(true)
        vm.setSearchQuery("привет")
        advance(ChatListViewModel.SEARCH_DELAY_MS)
        assertEquals(1, vm.state.value.messages.size)
        vm.setSearchActive(false)
        assertTrue(vm.state.value.messages.isEmpty())
        vm.setSearchActive(true)
        vm.setSearchQuery("п")
        assertTrue(vm.state.value.messages.isEmpty())
    }

    @Test
    fun snippetIsOneShortLine() {
        assertEquals("а б", FoundMessageItem.snippet("  а\n\tб "))
        val long = FoundMessageItem.snippet("слово ".repeat(100))
        assertTrue(long.endsWith("…"))
        assertTrue(long.length <= 161)
    }

    @Test
    fun pinGoesOnTopImmediately() {
        repo.pinFailure = CoreFailure("NETWORK", null)
        repo.chats.value = listOf(chat("a"), chat("b", at = now - 100))
        vm.togglePin("b")
        assertEquals(listOf("b" to true), repo.pins)
        // Ошибка сервера возвращает строку на место и показывает текст.
        assertEquals(listOf("a", "b"), vm.state.value.items.map { it.id })
        assertEquals("Нет соединения с сервером", vm.messages.value)
    }

    @Test
    fun pinReorderNeedsTwoPinsInAllChats() {
        repo.chats.value = listOf(chat("a", pin = 0), chat("b"))
        assertFalse(vm.state.value.canReorderPins)
        vm.startPinReorder()
        assertFalse(vm.state.value.isReorderingPins)

        repo.chats.value = listOf(chat("a", pin = 0), chat("b", pin = 1), chat("c", ChatType.CHANNEL))
        assertTrue(vm.state.value.canReorderPins)
        vm.setSearchActive(true)
        assertFalse(vm.state.value.canReorderPins)
        vm.setSearchActive(false)
        repo.folders.value = listOf(ServerFolder("f", "Каналы", filters = listOf("CHANNEL")))
        vm.selectFolder("f")
        assertFalse(vm.state.value.canReorderPins)

        // Режим открывает папку «Все», а когда закреплённых меньше двух — закрывается сам.
        vm.selectFolder("all")
        vm.startPinReorder()
        assertTrue(vm.state.value.isReorderingPins)
        repo.chats.value = listOf(chat("a", pin = 0), chat("b"), chat("c", ChatType.CHANNEL))
        assertFalse(vm.state.value.isReorderingPins)
    }

    @Test
    fun reorderShowsAtOnceAndWaitsForServer() {
        repo.chats.value = listOf(chat("a", pin = 0), chat("b", pin = 1), chat("c", pin = 2), chat("x"))
        val gate = CompletableDeferred<Unit>()
        repo.reorderGate = gate
        vm.reorderPinned(listOf("c", "a", "b"))
        assertEquals(listOf("c", "a", "b", "x"), vm.state.value.items.map { it.id })
        assertEquals(listOf(listOf("c", "a", "b")), repo.reorders)
        // Снимок без нового порядка (пришло сообщение) не возвращает строки на старые места.
        repo.chats.value = listOf(chat("a", pin = 0), chat("b", pin = 1), chat("c", pin = 2), chat("x", unread = 1))
        assertEquals(listOf("c", "a", "b", "x"), vm.state.value.items.map { it.id })
        gate.complete(Unit)
        assertEquals(listOf("c", "a", "b", "x"), vm.state.value.items.map { it.id })
        // Дальше порядок снова берётся с сервера: например, переставили на другом устройстве.
        repo.chats.value = listOf(chat("a", pin = 1), chat("b", pin = 0), chat("c", pin = 2), chat("x"))
        assertEquals(listOf("b", "a", "c", "x"), vm.state.value.items.map { it.id })
    }

    @Test
    fun reorderFailureRestoresServerOrder() {
        repo.reorderFailure = CoreFailure("NETWORK", null)
        repo.chats.value = listOf(chat("a", pin = 0), chat("b", pin = 1))
        vm.reorderPinned(listOf("b", "a"))
        assertEquals(listOf("a", "b"), vm.state.value.items.map { it.id })
        assertEquals("Нет соединения с сервером", vm.messages.value)
    }

    @Test
    fun reorderIgnoresStaleOrUnchangedOrder() {
        repo.chats.value = listOf(chat("a", pin = 0), chat("b", pin = 1), chat("c"))
        vm.reorderPinned(listOf("a", "b"))
        vm.reorderPinned(listOf("b", "c"))
        vm.reorderPinned(listOf("b"))
        assertTrue(repo.reorders.isEmpty())
    }

    @Test
    fun movePinnedByOneStep() {
        repo.chats.value = listOf(chat("a", pin = 0), chat("b", pin = 1), chat("c", pin = 2))
        vm.movePinned("a", 1)
        assertEquals(listOf("b", "a", "c"), repo.reorders.last())
        vm.movePinned("c", -5)
        assertEquals(listOf("c", "b", "a"), repo.reorders.last())
        vm.movePinned("c", -1)
        assertEquals(2, repo.reorders.size)
    }

    @Test
    fun pinLimit() {
        repo.chats.value = (0 until 10).map { chat("p$it", pin = it) } + chat("x")
        vm.togglePin("x")
        assertTrue(repo.pins.isEmpty())
        assertEquals("Можно закрепить не больше 10 чатов", vm.messages.value)
    }

    @Test
    fun typingShownInPreview() {
        repo.chats.value = listOf(chat("1"))
        repo.typing.value = mapOf("1" to listOf(app.maxly.domain.Typist(null)))
        assertEquals("печатает…", vm.state.value.items.single().preview)
    }

    @Test
    fun toggleReadMarksLocallyAndReadsOnServer() {
        repo.chats.value = listOf(chat("a"), chat("b", unread = 3))
        vm.toggleRead("a")
        assertTrue(vm.state.value.items.first { it.id == "a" }.isUnread)
        assertEquals(setOf("a"), marks.markedUnread)
        assertTrue(repo.reads.isEmpty())
        vm.toggleRead("a")
        assertFalse(vm.state.value.items.first { it.id == "a" }.isUnread)
        assertEquals(emptySet<String>(), marks.markedUnread)
        vm.toggleRead("b")
        assertEquals(listOf("b"), repo.reads)
    }

    @Test
    fun openingClearsManualMark() {
        marks.markedUnread = setOf("a")
        repo.chats.value = listOf(chat("a"))
        assertTrue(vm.state.value.items.single().isUnread)
        vm.opened("a")
        assertFalse(vm.state.value.items.single().isUnread)
        assertTrue(marks.markedUnread.isEmpty())
    }

    @Test
    fun toggleMuteIsOptimisticAndRollsBack() {
        repo.chats.value = listOf(chat("a"))
        vm.toggleMute("a")
        assertTrue(vm.state.value.items.single().isMuted)
        assertEquals(listOf("a" to true), repo.mutes)
        repo.muteFailure = CoreFailure("SERVER", "boom")
        vm.toggleMute("a")
        assertTrue(vm.state.value.items.single().isMuted)
        assertTrue(vm.messages.value != null)
    }

    @Test
    fun draftsShowInPreviewAfterReload() {
        repo.chats.value = listOf(chat("a"))
        assertEquals("текст", vm.state.value.items.single().preview)
        marks.stored = mapOf("a" to ChatDraft("привет", now))
        vm.reloadLocal()
        assertTrue(vm.state.value.items.single().preview.contains("привет"))
    }

    @Test
    fun laterOfLocalAndServerDraftIsShown() {
        val server = FakeDraftServer()
        server.stored.value = mapOf("a" to ChatDraft("с телефона", now - 1_000))
        val vm = ChatListViewModel(repo, connection, ChatListFormatter(ZoneOffset.UTC), now = { now }, local = marks, serverDrafts = server)
        repo.chats.value = listOf(chat("a"), chat("b"))
        assertTrue(vm.state.value.items.first { it.id == "a" }.preview.contains("с телефона"))
        marks.stored = mapOf("a" to ChatDraft("отсюда", now - 500))
        vm.reloadLocal()
        assertTrue(vm.state.value.items.first { it.id == "a" }.preview.contains("отсюда"))
        server.stored.value = mapOf("a" to ChatDraft("ещё новее", now), "b" to ChatDraft("второй", now))
        assertTrue(vm.state.value.items.first { it.id == "a" }.preview.contains("ещё новее"))
        assertTrue(vm.state.value.items.first { it.id == "b" }.preview.contains("второй"))
        // Стирание на другом устройстве в то же время, что и наш черновик: побеждает стирание.
        server.discardedElsewhere("a", now)
        assertFalse(vm.state.value.items.first { it.id == "a" }.preview.contains("ещё новее"))
    }

    @Test
    fun forwardTargetsSkipCurrentArchivedAndReadOnly() {
        repo.chats.value = listOf(
            chat("a", at = now - 10), chat("b", pin = 0), chat("c"),
            chat("d").copy(isArchived = true), chat("e", type = ChatType.CHANNEL).copy(canWrite = false),
        )
        assertEquals(listOf("b", "a"), vm.forwardTargets(excluding = "c").map { it.id })
    }

    @Test
    fun emptySearchShowsRecentChatsThatStillExist() {
        val store = FakeRecents(listOf("b", "gone", "a"))
        val model = listWith(store)
        repo.chats.value = listOf(chat("a"), chat("b"))
        model.setSearchActive(true)
        assertEquals(listOf("b", "a"), model.state.value.recent.map { it.id })
        model.setSearchQuery("чат")
        assertTrue(model.state.value.recent.isEmpty())
        model.setSearchQuery("  ")
        model.selectSearchResult("a")
        assertEquals(listOf("a", "b"), model.state.value.recent.map { it.id })
        assertEquals(listOf("a", "b", "gone"), store.saved)
        model.selectSearchResult("a")
        assertEquals(listOf("a", "b", "gone"), store.saved)
        model.removeRecent("gone")
        assertEquals(listOf("a", "b"), store.saved)
        model.setSearchActive(false)
        assertTrue(model.state.value.recent.isEmpty())
        model.setSearchActive(true)
        assertEquals(listOf("a", "b"), model.state.value.recent.map { it.id })
    }

    @Test
    fun openingOutsideSearchDoesNotRememberTheChat() {
        val store = FakeRecents()
        val model = listWith(store)
        repo.chats.value = listOf(chat("a"))
        model.opened("a")
        assertTrue(store.saved.isEmpty())
    }

    @Test
    fun recentSearchKeepsTwentyAndReloadDropsClearedIds() {
        val store = FakeRecents()
        val model = listWith(store)
        repeat(21) { model.selectSearchResult("c$it") }
        assertEquals(20, store.saved.size)
        assertEquals("c20", store.saved.first())
        assertFalse(store.saved.contains("c0"))
        store.clear()
        model.reloadLocal()
        model.setSearchActive(true)
        assertTrue(model.state.value.recent.isEmpty())
        assertTrue(store.saved.isEmpty())
    }

    @Test
    fun preferenceRecentSearchesRoundTrip() {
        val prefs = MemPrefs()
        val store = PreferenceRecentSearches(prefs)
        store.add(" a ")
        store.add("b")
        store.add("a")
        assertEquals(listOf("a", "b"), store.recent())
        assertEquals(listOf("a", "b"), RecentSearchList.decode(prefs.map[PreferenceRecentSearches.KEY]))
        store.remove("b")
        assertEquals(listOf("a"), PreferenceRecentSearches(prefs).recent())
        store.clear()
        assertTrue(store.recent().isEmpty())
    }

    @Test
    fun preferenceRecentSearchesReadsTheListSavedBeforeTheRename() {
        val prefs = MemPrefs()
        prefs.put(PreferenceRecentSearches.LEGACY_KEY, "a\nb")
        val store = PreferenceRecentSearches(prefs)
        assertEquals(listOf("a", "b"), store.recent())
        store.add("c")
        assertEquals(listOf("c", "a", "b"), RecentSearchList.decode(prefs.map[PreferenceRecentSearches.KEY]))
        store.clear()
        assertTrue(store.recent().isEmpty())
        assertTrue(prefs.map[PreferenceRecentSearches.LEGACY_KEY].isNullOrEmpty())
    }

    private fun listWith(store: RecentSearchStore) = ChatListViewModel(
        repo, connection, ChatListFormatter(ZoneOffset.UTC), now = { now }, local = marks, recents = store,
    )
}

private class FakeRecents(start: List<String> = emptyList()) : RecentSearchStore {
    val saved = start.toMutableList()
    override fun recent(): List<String> = saved.toList()
    override fun add(chatId: String) {
        val next = RecentSearchList.add(saved, chatId)
        saved.clear()
        saved.addAll(next)
    }
    override fun remove(chatId: String) {
        val next = RecentSearchList.remove(saved, chatId)
        saved.clear()
        saved.addAll(next)
    }
    override fun clear() {
        saved.clear()
    }
}

private class MemPrefs : PreferenceStore {
    val map = HashMap<String, String>()
    override fun get(key: String): String? = map[key]
    override fun put(key: String, value: String) {
        map[key] = value
    }
}
