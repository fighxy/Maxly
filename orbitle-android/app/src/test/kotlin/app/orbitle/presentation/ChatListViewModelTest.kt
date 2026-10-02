package app.orbitle.presentation

import app.orbitle.MainDispatcherRule
import app.orbitle.data.ChatRepository
import app.orbitle.data.CoreFailure
import app.orbitle.domain.Chat
import app.orbitle.domain.ChatDraft
import app.orbitle.domain.ChatType
import app.orbitle.domain.ConnectionState
import app.orbitle.domain.ServerFolder
import app.orbitle.presentation.chatlist.ChatListContent
import app.orbitle.presentation.chatlist.ChatListFormatter
import app.orbitle.presentation.chatlist.ChatListViewModel
import app.orbitle.presentation.chatlist.ChatLocalMarks
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
}
