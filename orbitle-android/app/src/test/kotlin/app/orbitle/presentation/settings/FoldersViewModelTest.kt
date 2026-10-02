package app.orbitle.presentation.settings

import app.orbitle.MainDispatcherRule
import app.orbitle.data.CoreFolderRepository
import app.orbitle.data.FolderRepository
import app.orbitle.domain.ServerFolder
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private class FakeFolders(initial: List<ServerFolder>?) : FolderRepository {
    override val folders = MutableStateFlow(initial)
    val calls = mutableListOf<String>()
    var failing = false
    override suspend fun reload() {
        calls += "reload"
    }
    override suspend fun create(title: String, chatIds: List<String>, filters: List<String>) {
        check(!failing) { "нет сети" }
        calls += "create $title $chatIds $filters"
    }
    override suspend fun rename(folderId: String, title: String) {
        calls += "rename $folderId $title"
    }
    override suspend fun setChats(folderId: String, chatIds: List<String>) {
        calls += "chats $folderId $chatIds"
    }
    override suspend fun delete(folderId: String) {
        check(!failing) { "нет сети" }
        calls += "delete $folderId"
    }
    override suspend fun reorder(order: List<String>) {
        check(!failing) { "нет сети" }
        calls += "order $order"
    }
}

class FoldersViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    private val all = ServerFolder("all.chat.folder", "Все", isAllChats = true)
    private val work = ServerFolder("w", "Работа", chatIds = listOf("1", "2"))
    private val bots = ServerFolder("b", "Боты", filters = listOf("10"))
    private val family = ServerFolder("f", "Семья", chatIds = listOf("3"))

    @Test
    fun `all chats goes first and is not editable`() {
        val model = FoldersViewModel(FakeFolders(listOf(work, all, bots)))
        assertEquals(listOf("all.chat.folder", "w", "b"), model.state.value.folders!!.map { it.id })
        assertEquals(listOf("w", "b"), model.state.value.editable.map { it.id })
        model.delete(all)
        model.rename(all, "Другое")
        assertEquals(3, model.state.value.folders!!.size)
    }

    @Test
    fun `only missing type folders are offered`() {
        val repo = FakeFolders(listOf(all, bots))
        val model = FoldersViewModel(repo)
        assertEquals(listOf("Личные", "Каналы"), model.state.value.missingTypeFolders.map { it.first })
        model.addTypeFolders()
        assertEquals(listOf("create Личные [] [4]", "create Каналы [] [2]"), repo.calls.filter { it.startsWith("create") })
    }

    @Test
    fun `moving sends the full order with all chats first`() {
        val repo = FakeFolders(listOf(all, work, bots, family))
        val model = FoldersViewModel(repo)
        model.move(family, -1)
        assertEquals("order [all.chat.folder, w, f, b]", repo.calls.last())
        assertEquals(listOf("w", "f", "b"), model.state.value.editable.map { it.id })
        val before = repo.calls.size
        model.move(work, -1)
        assertEquals(before, repo.calls.size)
    }

    @Test
    fun `failed delete restores the folder and shows an error`() {
        val repo = FakeFolders(listOf(all, work))
        repo.failing = true
        val model = FoldersViewModel(repo)
        model.delete(work)
        assertEquals(listOf("w"), model.state.value.editable.map { it.id })
        assertTrue(model.state.value.error!!.startsWith("Не удалось удалить папку"))
        assertFalse(model.state.value.working)
        model.dismissError()
        assertNull(model.state.value.error)
    }

    @Test
    fun `unchanged edits are not sent`() {
        val repo = FakeFolders(listOf(all, work))
        val model = FoldersViewModel(repo)
        model.rename(work, " Работа ")
        model.setChats(work, listOf("2", "1"))
        model.create("  ", listOf("1"))
        assertEquals(listOf("reload"), repo.calls)
        model.rename(work, "Офис")
        model.setChats(work, listOf("1"))
        assertEquals(listOf("reload", "rename w Офис", "chats w [1]"), repo.calls)
    }

    @Test
    fun `filters keep codes as numbers`() {
        assertEquals(listOf(4L, "BOT"), CoreFolderRepository.filtersOf(listOf(" 4 ", "BOT", "")))
    }

    @Test
    fun `summaries count chats in russian`() {
        assertEquals("1 чат", chatsCount(1))
        assertEquals("3 чата", chatsCount(3))
        assertEquals("11 чатов", chatsCount(11))
        assertEquals("22 чата", chatsCount(22))
        assertEquals("2 чата", folderSummary(work, 2))
        assertEquals("0 чатов · сами: боты", folderSummary(bots, 0))
        assertEquals("сами: личные, каналы", folderFilterSummary(ServerFolder("x", "x", filters = listOf("4", "DIALOG", "2"))))
        assertEquals("по правилам сервера", folderFilterSummary(ServerFolder("x", "x", filters = listOf("5"))))
    }
}
