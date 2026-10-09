package app.maxly.presentation.settings

import app.maxly.MainDispatcherRule
import app.maxly.data.CoreFolderRepository
import app.maxly.data.FolderRepository
import app.maxly.domain.ServerFolder
import app.maxly.presentation.common.ListOrder
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
    fun `drop with a new order sends it once with all chats first`() {
        val repo = FakeFolders(listOf(all, work, bots, family))
        val model = FoldersViewModel(repo)
        model.reorder(listOf("f", "w", "b"))
        assertEquals(listOf("order [all.chat.folder, f, w, b]"), repo.calls.filter { it.startsWith("order") })
        assertEquals(listOf("all.chat.folder", "f", "w", "b"), model.state.value.folders!!.map { it.id })
        assertFalse(model.state.value.working)
    }

    @Test
    fun `drop with the same order sends nothing`() {
        val repo = FakeFolders(listOf(all, work, bots))
        val model = FoldersViewModel(repo)
        model.reorder(listOf("w", "b"))
        assertTrue(repo.calls.none { it.startsWith("order") })
        assertFalse(model.state.value.working)
    }

    @Test
    fun `failed reorder restores the server order and shows an error`() {
        val repo = FakeFolders(listOf(all, work, bots, family))
        repo.failing = true
        val model = FoldersViewModel(repo)
        model.reorder(listOf("b", "f", "w"))
        assertEquals(listOf("w", "b", "f"), model.state.value.editable.map { it.id })
        assertTrue(model.state.value.error!!.startsWith("Не удалось изменить порядок папок"))
        assertFalse(model.state.value.working)
    }

    @Test
    fun `all chats can not be moved`() {
        val repo = FakeFolders(listOf(all, work, bots))
        val model = FoldersViewModel(repo)
        model.move(all, 1)
        // Порядок с «Все» среди редактируемых или с чужим набором отбрасывается.
        model.reorder(listOf("w", "all.chat.folder", "b"))
        model.reorder(listOf("b", "x"))
        model.reorder(listOf("b", "b"))
        model.reorder(listOf("b"))
        assertTrue(repo.calls.none { it.startsWith("order") })
        assertEquals(listOf("all.chat.folder", "w", "b"), model.state.value.folders!!.map { it.id })
    }

    @Test
    fun `accessibility moves go through the same reorder`() {
        val repo = FakeFolders(listOf(all, work, bots, family))
        val model = FoldersViewModel(repo)
        model.move(work, 1)
        model.move(work, 5)
        assertEquals(listOf("order [all.chat.folder, b, w, f]", "order [all.chat.folder, b, f, w]"), repo.calls.filter { it.startsWith("order") })
        model.move(work, 1)
        assertEquals(2, repo.calls.count { it.startsWith("order") })
    }

    @Test
    fun `folder order moves and clamps`() {
        val ids = listOf("a", "b", "c", "d")
        assertEquals(listOf("b", "c", "a", "d"), ListOrder.moved(ids, 0, 2))
        assertEquals(listOf("d", "a", "b", "c"), ListOrder.moved(ids, 3, 0))
        assertEquals(listOf("a", "c", "d", "b"), ListOrder.moved(ids, 1, 9))
        assertEquals(listOf("b", "a", "c", "d"), ListOrder.moved(ids, 1, -4))
        assertEquals(ids, ListOrder.moved(ids, 2, 2))
        assertEquals(ids, ListOrder.moved(ids, 7, 0))
        assertEquals(emptyList<String>(), ListOrder.moved(emptyList(), 0, 1))
    }

    @Test
    fun `folder order recognizes permutations`() {
        assertTrue(ListOrder.isPermutation(listOf("b", "a"), listOf("a", "b")))
        assertFalse(ListOrder.isPermutation(listOf("a", "a"), listOf("a", "b")))
        assertFalse(ListOrder.isPermutation(listOf("a"), listOf("a", "b")))
        assertFalse(ListOrder.isPermutation(listOf("a", "c"), listOf("a", "b")))
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
