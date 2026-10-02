package app.orbitle.presentation

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatRepository
import app.orbitle.data.CoreFailure
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.ChatSearchResult
import app.orbitle.domain.ChatType
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.ServerFolder
import app.orbitle.presentation.chatlist.ChatListContent
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.presentation.chatlist.ChatLocalMarks
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class FakeChats : ChatRepository {
    override val chats = MutableStateFlow<List<Chat>?>(null)
    override val folders = MutableStateFlow<List<ServerFolder>>(emptyList())
    override val typing = MutableStateFlow<Map<String, List<String>>>(emptyMap())
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
    fun pinLimit() {
        repo.chats.value = (0 until 10).map { chat("p$it", pin = it) } + chat("x")
        vm.togglePin("x")
        assertTrue(repo.pins.isEmpty())
        assertEquals("Можно закрепить не больше 10 чатов", vm.messages.value)
    }

    @Test
    fun typingShownInPreview() {
        repo.chats.value = listOf(chat("1"))
        repo.typing.value = mapOf("1" to listOf("5"))
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
    fun forwardTargetsSkipCurrentArchivedAndReadOnly() {
        repo.chats.value = listOf(
            chat("a", at = now - 10), chat("b", pin = 0), chat("c"),
            chat("d").copy(isArchived = true), chat("e", type = ChatType.CHANNEL).copy(canWrite = false),
        )
        assertEquals(listOf("b", "a"), vm.forwardTargets(excluding = "c").map { it.id })
    }
}
