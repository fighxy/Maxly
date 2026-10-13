package app.maxly.presentation

import app.maxly.MainDispatcherRule
import app.maxly.data.FolderRepository
import app.maxly.domain.Chat
import app.maxly.domain.ChatType
import app.maxly.domain.ConnectionState
import app.maxly.domain.ServerFolder
import app.maxly.presentation.chatlist.ChatListFormatter
import app.maxly.presentation.chatlist.ChatListViewModel
import app.maxly.presentation.chatlist.FolderTabMenu
import app.maxly.presentation.chatlist.FolderTabMenu.Entry
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

class FolderTabMenuTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun allTabEditsFoldersAndReordersOnlyWithTwoOwnFolders() {
        assertEquals(
            listOf(Entry.EditFolders, Entry.Reorder),
            FolderTabMenu.entries(isAll = true, editable = true, hasUnread = true, allMuted = false, hasChats = true, folderCount = 2),
        )
        assertEquals(
            listOf(Entry.EditFolders),
            FolderTabMenu.entries(isAll = true, editable = true, hasUnread = false, allMuted = false, hasChats = true, folderCount = 1),
        )
        assertEquals(emptyList<Entry>(), FolderTabMenu.entries(isAll = true, editable = false, hasUnread = true, allMuted = false, hasChats = true, folderCount = 3))
    }

    @Test
    fun ownFolderHasTelegramOrder() {
        val entries = FolderTabMenu.entries(isAll = false, editable = true, hasUnread = true, allMuted = false, hasChats = true, folderCount = 3)
        assertEquals(
            listOf("Настроить папку", "Добавить чаты", "Прочитать все", "Выкл. уведомления", "Удалить", "Изменить порядок"),
            entries.map { it.title },
        )
        assertTrue(Entry.Delete.isDanger)
        assertTrue(Entry.Reorder.separated)
    }

    @Test
    fun readAllOnlyWithUnreadAndMuteFlips() {
        val entries = FolderTabMenu.entries(isAll = false, editable = true, hasUnread = false, allMuted = true, hasChats = true, folderCount = 1)
        assertEquals(listOf(Entry.EditFolder, Entry.AddChats, Entry.Mute(true), Entry.Delete), entries)
        assertEquals("Вкл. уведомления", Entry.Mute(true).title)
    }

    @Test
    fun localFilterTabOnlyReadsAndMutes() {
        val entries = FolderTabMenu.entries(isAll = false, editable = false, hasUnread = true, allMuted = false, hasChats = true, folderCount = 0)
        assertEquals(listOf(Entry.ReadAll, Entry.Mute(false)), entries)
    }

    // Действия модели списка

    private val now = 1_790_683_200_000L
    private val formatter = ChatListFormatter(ZoneOffset.UTC)

    private fun chat(id: String, unread: Int = 0, muted: Boolean = false) =
        Chat(id = id, title = "Чат $id", type = ChatType.PRIVATE, lastMessageId = "1", unreadCount = unread, updatedAtMs = now, preview = "текст", isMuted = muted, peerId = "7$id")

    private val all = ServerFolder("all", "Все", isAllChats = true)
    private val work = ServerFolder("f1", "Работа", chatIds = listOf("1", "2"))
    private val home = ServerFolder("f2", "Дом", chatIds = listOf("3"))

    private class Folders : FolderRepository {
        override val folders = MutableStateFlow<List<ServerFolder>?>(null)
        val calls = mutableListOf<String>()
        override suspend fun reload() = Unit
        override suspend fun create(title: String, chatIds: List<String>, filters: List<String>) = Unit
        override suspend fun rename(folderId: String, title: String) {
            calls += "rename $folderId $title"
        }
        override suspend fun setChats(folderId: String, chatIds: List<String>) {
            calls += "chats $folderId $chatIds"
        }
        override suspend fun delete(folderId: String) {
            calls += "delete $folderId"
        }
        override suspend fun reorder(order: List<String>) = Unit
    }

    private val repo = FakeChats()
    private val folders = Folders()
    private val vm by lazy {
        ChatListViewModel(repo, MutableStateFlow(ConnectionState.ONLINE), formatter, now = { now }, local = FakeMarks(), folderEditor = folders)
    }

    private fun setUp() {
        repo.chats.value = listOf(chat("1", unread = 3), chat("2"), chat("3", unread = 1, muted = true))
        repo.folders.value = listOf(all, work, home)
    }

    @Test
    fun menuForFolderAndAll() {
        setUp()
        assertEquals(listOf(Entry.EditFolders, Entry.Reorder), vm.folderMenu("all"))
        assertEquals(
            listOf(Entry.EditFolder, Entry.AddChats, Entry.ReadAll, Entry.Mute(false), Entry.Delete, Entry.Reorder),
            vm.folderMenu("f1"),
        )
        assertEquals(Entry.Mute(true), vm.folderMenu("f2").first { it is Entry.Mute })
        assertEquals(emptyList<Entry>(), vm.folderMenu("missing"))
    }

    @Test
    fun readFolderReadsOnlyUnreadMembers() {
        setUp()
        vm.readFolder("f1")
        assertEquals(listOf("1"), repo.reads)
    }

    @Test
    fun muteFolderSkipsAlreadyMuted() {
        setUp()
        vm.setFolderMuted("f1", true)
        assertEquals(listOf("1" to true, "2" to true), repo.mutes)
        assertEquals(Entry.Mute(true), vm.folderMenu("f1").first { it is Entry.Mute })
        vm.setFolderMuted("f2", true)
        assertEquals(2, repo.mutes.size)
    }

    @Test
    fun hiddenAllOpensFirstOwnFolder() {
        val hidden = MutableStateFlow(true)
        val model = ChatListViewModel(repo, MutableStateFlow(ConnectionState.ONLINE), formatter, now = { now }, local = FakeMarks(), folderEditor = folders, hidesAllChats = hidden)
        setUp()
        assertEquals(listOf("f1", "f2"), model.state.value.folders.map { it.id })
        assertEquals("f1", model.state.value.selectedFolderId)
        assertEquals(listOf("1", "2"), model.state.value.items.map { it.id })
        hidden.value = false
        assertEquals(listOf("all", "f1", "f2"), model.state.value.folders.map { it.id })
    }

    @Test
    fun hiddenAllStaysWithoutOwnFoldersAndOneFolderStillShowsStrip() {
        val model = ChatListViewModel(repo, MutableStateFlow(ConnectionState.ONLINE), formatter, now = { now }, local = FakeMarks(), folderEditor = folders, hidesAllChats = MutableStateFlow(true))
        repo.chats.value = listOf(chat("1"), chat("3"))
        assertEquals(listOf("all"), model.state.value.folders.map { it.id })
        assertEquals(false, model.state.value.showsFolders)
        repo.folders.value = listOf(all, home)
        assertEquals(listOf("f2"), model.state.value.folders.map { it.id })
        assertTrue(model.state.value.showsFolders)
        assertEquals(listOf("3"), model.state.value.items.map { it.id })
    }

    @Test
    fun saveRenamesOnlyOnChangeAndDeleteReturnsToAll() {
        setUp()
        vm.saveFolder("f1", " Работа ", listOf("2", "1"))
        assertEquals(emptyList<String>(), folders.calls)
        vm.saveFolder("f1", "Офис", listOf("1", "2", "3"))
        assertEquals(listOf("rename f1 Офис", "chats f1 [1, 2, 3]"), folders.calls)
        vm.selectFolder("f2")
        vm.deleteFolder("f2")
        assertEquals("delete f2", folders.calls.last())
        assertEquals("all", vm.state.value.selectedFolderId)
        assertEquals("Папка «Дом» удалена", vm.messages.value)
    }
}
