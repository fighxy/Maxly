package app.maxly.presentation.settings

import app.maxly.MainDispatcherRule
import app.maxly.data.StorageRepository
import app.maxly.domain.StorageCategory
import app.maxly.domain.StorageUsage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test

private class FakeStorage : StorageRepository {
    val sizes = mutableMapOf(StorageCategory.PHOTOS to 3_000L, StorageCategory.FILES to 1_000L)
    val cleared = mutableListOf<Set<StorageCategory>>()
    override suspend fun usage() = StorageUsage(sizes.toMap())
    override suspend fun clear(categories: Set<StorageCategory>) {
        cleared += categories
        categories.forEach { sizes.remove(it) }
    }
}

class StorageViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test
    fun `everything is selected and shares add up`() {
        val model = StorageViewModel(FakeStorage())
        val s = model.state.value
        assertEquals(4_000L, s.usage!!.total)
        assertEquals(4_000L, s.selectedBytes)
        assertEquals(0.75f, s.share(StorageCategory.PHOTOS), 0.001f)
        assertEquals(0f, s.share(StorageCategory.OTHER), 0.001f)
    }

    @Test
    fun `clears only the selected categories`() {
        val repo = FakeStorage()
        val model = StorageViewModel(repo)
        model.toggle(StorageCategory.PHOTOS)
        assertEquals(1_000L, model.state.value.selectedBytes)
        model.clearSelected()
        assertEquals(listOf(StorageCategory.FILES, StorageCategory.OUTGOING, StorageCategory.OTHER).toSet(), repo.cleared.single())
        assertEquals(3_000L, model.state.value.usage!!.total)
        assertFalse(model.state.value.clearing)
    }

    @Test
    fun `sizes are formatted in russian units`() {
        assertEquals("0 Б", StorageViewModel.format(0))
        assertEquals("512 КБ", StorageViewModel.format(512 * 1024))
        assertEquals("1,5 МБ", StorageViewModel.format(1_572_864))
        assertEquals("2 ГБ", StorageViewModel.format(2L shl 30))
        assertEquals("176 МБ", StorageViewModel.format(184_320_000))
    }
}
