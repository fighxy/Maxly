package app.maxly.presentation.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReadVisibilityTest {

    /** Строка высотой 100, целиком от [offset]. */
    private fun row(index: Int, offset: Int, key: String = index.toString()) =
        FeedItemFrame(index, key, offset, 100)

    @Test
    fun fractionAtTheThresholdAndBeyond() {
        // Видимая область 0…1000.
        assertEquals(0.29f, ReadVisibility.visibleFraction(0, 100, 71, 1000), 0.0001f)
        assertEquals(0.30f, ReadVisibility.visibleFraction(0, 100, 70, 1000), 0.0001f)
        assertEquals(1f, ReadVisibility.visibleFraction(100, 100, 0, 1000), 0.0001f)
        // Нулевая высота и пустая область ничего не показывают.
        assertEquals(0f, ReadVisibility.visibleFraction(0, 0, 0, 1000), 0.0001f)
        assertEquals(0f, ReadVisibility.visibleFraction(0, 100, 500, 500), 0.0001f)
    }

    @Test
    fun newestSeenNeedsThirtyPercent() {
        // Прямая лента: новые в конце. Первая строка видна на 29 %, вторая целиком.
        val items = listOf(row(0, -71), row(1, 29), row(2, 129))
        assertEquals("2", ReadVisibility.newestVisibleKey(items, 0, 1000, reverseLayout = false))
        // Вторая выглядывает на 29 % — её ещё не видно, читается первая.
        val peeking = listOf(row(0, 0), row(1, 971))
        assertEquals("0", ReadVisibility.newestVisibleKey(peeking, 0, 1000, reverseLayout = false))
        // Ровно 30 % — уже видно.
        val just = listOf(row(0, 0), row(1, 970))
        assertEquals("1", ReadVisibility.newestVisibleKey(just, 0, 1000, reverseLayout = false))
    }

    @Test
    fun reverseLayoutCountsNewestTowardTheStart() {
        // Перевёрнутая лента: смещения считаются от низа, новые — в начале списка, у низа.
        // Новая строка 0 почти ушла под низ (видно 29 %): читается строка 1 над ней.
        val newestPeeking = listOf(row(0, -71), row(1, 29), row(2, 129))
        assertEquals("1", ReadVisibility.newestVisibleKey(newestPeeking, 0, 1000, reverseLayout = true))
        // Ровно 30 % — уже видна она.
        val newestJust = listOf(row(0, -70), row(1, 30), row(2, 130))
        assertEquals("0", ReadVisibility.newestVisibleKey(newestJust, 0, 1000, reverseLayout = true))
        // Те же строки в обычной ленте: новые в конце списка, читается последняя видимая.
        assertEquals("2", ReadVisibility.newestVisibleKey(newestPeeking, 0, 1000, reverseLayout = false))
    }

    @Test
    fun contentPaddingHidesRowsUnderOverlays() {
        // Перевёрнутая лента: отступ в начале — это низ. Строка у низа видна над ним на 29 %.
        val atBottom = listOf(row(0, 0), row(1, 100))
        assertEquals("1", ReadVisibility.newestVisibleKey(atBottom, 0, 1000, reverseLayout = true, beforeContent = 71))
        // Ровно 30 % — уже прочитано.
        assertEquals("0", ReadVisibility.newestVisibleKey(atBottom, 0, 1000, reverseLayout = true, beforeContent = 70))
        // Отступ в конце прячет верх: обычная лента, новая строка под верхней накладкой на 71 %.
        val underTop = listOf(row(0, 0), row(1, 900))
        assertEquals("0", ReadVisibility.newestVisibleKey(underTop, 0, 1000, reverseLayout = false, afterContent = 71))
        assertEquals("1", ReadVisibility.newestVisibleKey(underTop, 0, 1000, reverseLayout = false, afterContent = 70))
        // Накладки перекрыли всю область — читать нечего.
        assertNull(ReadVisibility.newestVisibleKey(underTop, 0, 1000, reverseLayout = false, beforeContent = 600, afterContent = 600))
    }

    @Test
    fun rowsWithoutKeyAreSkipped() {
        val items = listOf(FeedItemFrame(0, null, 0, 1000), row(1, 0))
        assertEquals("1", ReadVisibility.newestVisibleKey(items, 0, 500, reverseLayout = false))
    }
}
