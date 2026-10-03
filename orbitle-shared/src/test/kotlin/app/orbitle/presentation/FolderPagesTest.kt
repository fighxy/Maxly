package app.orbitle.presentation

import app.orbitle.presentation.chatlist.FolderPages
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FolderPagesTest {
    private val ids = listOf("all", "new", "channels")

    @Test
    fun pageOfSelectedFolder() {
        assertEquals(0, FolderPages.pageOf(ids, "all"))
        assertEquals(2, FolderPages.pageOf(ids, "channels"))
        // Папки уже нет — первая страница.
        assertEquals(0, FolderPages.pageOf(ids, "gone"))
        assertEquals(0, FolderPages.pageOf(emptyList(), "all"))
    }

    @Test
    fun folderAtClampsThePage() {
        assertEquals("new", FolderPages.folderAt(ids, 1))
        assertEquals("all", FolderPages.folderAt(ids, -3))
        assertEquals("channels", FolderPages.folderAt(ids, 7))
        assertNull(FolderPages.folderAt(emptyList(), 0))
    }

    @Test
    fun settledPageSelectsOnlyAnotherFolder() {
        assertEquals("channels", FolderPages.selectionAfterSettle(ids, 2, "all"))
        assertNull(FolderPages.selectionAfterSettle(ids, 1, "new"))
        // Список стал короче, а пейджер ещё на старой странице: берётся последняя папка.
        assertEquals("channels", FolderPages.selectionAfterSettle(ids, 5, "all"))
        assertNull(FolderPages.selectionAfterSettle(emptyList(), 0, "all"))
    }

    @Test
    fun reorderKeepsTheSelectedFolderPage() {
        val reordered = listOf("all", "channels", "new")
        assertEquals(1, FolderPages.pageOf(reordered, "channels"))
        assertEquals("channels", FolderPages.folderAt(reordered, FolderPages.pageOf(reordered, "channels")))
    }

    @Test
    fun retainDropsRemovedFolders() {
        val positions = mapOf("all" to 3, "new" to 0, "gone" to 9)
        assertEquals(mapOf("all" to 3, "new" to 0), FolderPages.retain(positions, ids))
    }
}
