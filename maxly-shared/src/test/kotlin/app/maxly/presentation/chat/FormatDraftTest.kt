package app.maxly.presentation.chat

import app.maxly.domain.TextSpan
import app.maxly.domain.TextSpan.Kind.ANIMOJI
import app.maxly.domain.TextSpan.Kind.EMPHASIZED
import app.maxly.domain.TextSpan.Kind.LINK
import app.maxly.domain.TextSpan.Kind.MENTION
import app.maxly.domain.TextSpan.Kind.MONOSPACED
import app.maxly.domain.TextSpan.Kind.QUOTE
import app.maxly.domain.TextSpan.Kind.STRIKETHROUGH
import app.maxly.domain.TextSpan.Kind.STRONG
import app.maxly.domain.TextSpan.Kind.UNDERLINE
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FormatDraftTest {
    private fun span(kind: TextSpan.Kind, from: Int, length: Int, url: String? = null) = TextSpan(kind, from, length, url = url)

    private fun bold(from: Int, length: Int) = span(STRONG, from, length)

    /** Черновик с жирным «world» в «hello world». */
    private fun draft(vararg spans: TextSpan) = FormatDraft().apply { restore(spans.toList()) }

    // Правка текста

    @Test
    fun insertBeforeShiftsTheRange() {
        val d = draft(bold(6, 5))
        d.edit("hello world", "oh, hello world", cursor = 4)
        assertEquals(listOf(bold(10, 5)), d.spans)
    }

    @Test
    fun insertRightAtTheStartDoesNotExtend() {
        val d = draft(bold(6, 5))
        d.edit("hello world", "hello new world", cursor = 10)
        assertEquals(listOf(bold(10, 5)), d.spans)
    }

    @Test
    fun insertInsideGrowsTheRange() {
        val d = draft(bold(6, 5))
        d.edit("hello world", "hello wo-rld", cursor = 9)
        assertEquals(listOf(bold(6, 6)), d.spans)
    }

    @Test
    fun insertRightAfterTheEndDoesNotExtend() {
        val d = draft(bold(0, 5))
        d.edit("hello world", "hello! world", cursor = 6)
        assertEquals(listOf(bold(0, 5)), d.spans)
    }

    @Test
    fun insertAfterLeavesTheRangeAlone() {
        val d = draft(bold(0, 5))
        d.edit("hello world", "hello world!!", cursor = 13)
        assertEquals(listOf(bold(0, 5)), d.spans)
    }

    @Test
    fun deleteBeforeAndInside() {
        val d = draft(bold(6, 5))
        d.edit("hello world", "hllo world", cursor = 1)
        assertEquals(listOf(bold(5, 5)), d.spans)
        d.edit("hllo world", "hllo wrld", cursor = 6)
        assertEquals(listOf(bold(5, 4)), d.spans)
    }

    @Test
    fun deleteAcrossTheStartKeepsTheTail() {
        // «hello world», удалено «lo wo» (3..8): от жирного «world» остаётся «rld».
        val d = draft(bold(6, 5))
        d.edit("hello world", "helrld", cursor = 3)
        assertEquals(listOf(bold(3, 3)), d.spans)
    }

    @Test
    fun deleteAcrossTheEndKeepsTheHead() {
        // Жирное «hello», удалено «lo wo»: остаётся «hel».
        val d = draft(bold(0, 5))
        d.edit("hello world", "helrld", cursor = 3)
        assertEquals(listOf(bold(0, 3)), d.spans)
    }

    @Test
    fun deletingTheWholeRangeDropsIt() {
        val d = draft(bold(6, 5), span(EMPHASIZED, 0, 5))
        d.edit("hello world", "hello ", cursor = 6)
        assertEquals(listOf(span(EMPHASIZED, 0, 5)), d.spans)
        d.edit("hello ", "", cursor = 0)
        assertTrue(d.spans.isEmpty())
    }

    @Test
    fun replacingInsideOrTheWholeRangeKeepsTheFormat() {
        // Автозамена слова целиком: новое слово остаётся жирным.
        val d = draft(bold(6, 5))
        d.edit("hello world", "hello World", cursor = 7)
        assertEquals(listOf(bold(6, 5)), d.spans)
        d.edit("hello World", "hello planet", cursor = 12)
        assertEquals(listOf(bold(6, 6)), d.spans)
    }

    @Test
    fun replacingAcrossTheBoundaryDoesNotFormatTheNewText() {
        // «hello world» → выделено «o wo» (4..8) и заменено на «X»: жирное «world» сужается до «rld» после «X».
        val d = draft(bold(6, 5))
        d.edit("hello world", "hellXrld", cursor = 5)
        assertEquals(listOf(bold(5, 3)), d.spans)
    }

    @Test
    fun cursorPicksThePlaceAmongEqualLetters() {
        // «aa», жирная вторая «a». Вставка «a» в начало: без курсора правка нашлась бы в конце.
        val withCursor = draft(bold(1, 1))
        withCursor.edit("aa", "aaa", cursor = 1)
        assertEquals(listOf(bold(2, 1)), withCursor.spans)
        val guessed = draft(bold(1, 1))
        guessed.edit("aa", "aaa")
        assertEquals(listOf(bold(1, 1)), guessed.spans)
        // Backspace у курсора 1 в «aaa» с жирной последней «a».
        val deleted = draft(bold(2, 1))
        deleted.edit("aaa", "aa", cursor = 0)
        assertEquals(listOf(bold(1, 1)), deleted.spans)
    }

    @Test
    fun diffFindsTheEdit() {
        assertEquals(Triple(5, 0, 1), FormatDraft.diff("hello", "hello!", -1))
        assertEquals(Triple(0, 1, 0), FormatDraft.diff("hello", "ello", -1))
        assertEquals(Triple(1, 3, 2), FormatDraft.diff("hello", "hXYo", -1))
        assertEquals(Triple(0, 0, 1), FormatDraft.diff("aa", "aaa", 1))
        assertEquals(Triple(2, 0, 1), FormatDraft.diff("aa", "aaa", -1))
        assertEquals(Triple(0, 0, 3), FormatDraft.diff("", "abc", 3))
    }

    @Test
    fun severalRangesMoveTogether() {
        val d = draft(bold(0, 5), span(EMPHASIZED, 6, 5), span(MONOSPACED, 2, 6))
        d.edit("hello world", "hello, world", cursor = 6)
        assertEquals(listOf(bold(0, 5), span(MONOSPACED, 2, 7), span(EMPHASIZED, 7, 5)), d.spans)
    }

    // Кнопки панели

    @Test
    fun toggleAddsThenRemoves() {
        val d = FormatDraft()
        assertTrue(d.toggle(STRONG, 0, 5))
        assertEquals(listOf(bold(0, 5)), d.spans)
        assertTrue(d.isApplied(STRONG, 0, 5))
        assertTrue(d.isApplied(STRONG, 1, 3))
        assertFalse(d.toggle(STRONG, 0, 5))
        assertTrue(d.spans.isEmpty())
    }

    @Test
    fun toggleInsideSplitsTheRange() {
        val d = draft(bold(0, 11))
        assertFalse(d.toggle(STRONG, 5, 6))
        assertEquals(listOf(bold(0, 5), bold(6, 5)), d.spans)
    }

    @Test
    fun togglePartlyFormattedSelectionFormatsAllAndMerges() {
        val d = draft(bold(0, 3), bold(8, 3))
        assertFalse(d.isApplied(STRONG, 2, 9))
        assertTrue(d.toggle(STRONG, 2, 9))
        assertEquals(listOf(bold(0, 11)), d.spans)
    }

    @Test
    fun adjacentRangesOfTheSameKindMerge() {
        val d = draft(bold(0, 3))
        d.toggle(STRONG, 3, 5)
        assertEquals(listOf(bold(0, 5)), d.spans)
        // Другой вид рядом не сливается.
        d.toggle(UNDERLINE, 5, 7)
        assertEquals(listOf(bold(0, 5), span(UNDERLINE, 5, 2)), d.spans)
    }

    @Test
    fun kindsOverlapIndependently() {
        val d = FormatDraft()
        d.toggle(STRONG, 0, 5)
        d.toggle(EMPHASIZED, 3, 8)
        d.toggle(STRIKETHROUGH, 0, 8)
        assertEquals(listOf(bold(0, 5), span(STRIKETHROUGH, 0, 8), span(EMPHASIZED, 3, 5)), d.spans)
        d.toggle(STRONG, 0, 5)
        assertEquals(listOf(span(STRIKETHROUGH, 0, 8), span(EMPHASIZED, 3, 5)), d.spans)
    }

    @Test
    fun emptySelectionDoesNothing() {
        val d = FormatDraft()
        assertFalse(d.toggle(STRONG, 3, 3))
        assertFalse(d.isApplied(STRONG, 3, 3))
        d.setLink(2, 2, "https://a.ru")
        assertTrue(d.spans.isEmpty())
    }

    @Test
    fun linksReplaceEachOtherAndCanBeRemoved() {
        val d = FormatDraft()
        d.setLink(0, 5, "https://a.ru")
        assertEquals("https://a.ru", d.linkAt(0, 5))
        assertEquals("https://a.ru", d.linkAt(1, 2))
        d.setLink(3, 8, "https://b.ru")
        assertEquals(listOf(span(LINK, 0, 3, "https://a.ru"), span(LINK, 3, 5, "https://b.ru")), d.spans)
        // Соседние ссылки с разными адресами не сливаются, но вместе накрывают отрезок.
        assertNull(d.linkAt(0, 8))
        assertTrue(d.isApplied(LINK, 0, 8))
        d.setLink(0, 8, null)
        assertTrue(d.spans.isEmpty())
    }

    @Test
    fun sameLinkMerges() {
        val d = FormatDraft()
        d.setLink(0, 3, "https://a.ru")
        d.setLink(3, 6, "https://a.ru")
        assertEquals(listOf(span(LINK, 0, 6, "https://a.ru")), d.spans)
    }

    @Test
    fun linkMovesWithTextAndKeepsItsUrl() {
        val d = FormatDraft()
        d.setLink(6, 11, "https://a.ru")
        d.edit("hello world", "hi world", cursor = 2)
        assertEquals(listOf(span(LINK, 3, 5, "https://a.ru")), d.spans)
    }

    // Отправка и правка

    @Test
    fun trimmedShiftsByLeadingSpacesAndClipsTheEdges() {
        val d = draft(bold(0, 4), span(EMPHASIZED, 4, 3), span(UNDERLINE, 7, 3))
        // «  hi there  »: жирное «  hi», курсив « th», подчёркнутое «ere».
        val (text, spans) = d.trimmed("  hi there  ")
        assertEquals("hi there", text)
        assertEquals(listOf(bold(0, 2), span(EMPHASIZED, 2, 3), span(UNDERLINE, 5, 3)), spans)
        val (_, onlySpaces) = draft(bold(10, 2)).trimmed("  hi there  ")
        assertTrue(onlySpaces.isEmpty())
    }

    @Test
    fun restoreDropsMentionsAndBrokenRangesButKeepsOtherServerKinds() {
        val d = FormatDraft()
        d.restore(
            listOf(
                bold(0, 3),
                TextSpan(MENTION, 4, 5, userId = "7"),
                span(QUOTE, 0, 9),
                TextSpan(ANIMOJI, 10, 2, url = "lottie", entityId = "3"),
                bold(20, 4),
                span(EMPHASIZED, 2, 0),
            ),
            textLength = 12,
        )
        assertEquals(listOf(bold(0, 3), span(QUOTE, 0, 9), TextSpan(ANIMOJI, 10, 2, url = "lottie", entityId = "3")), d.spans)
    }

    @Test
    fun spansForClipsToTheText() {
        val d = draft(bold(0, 10))
        assertEquals(listOf(bold(0, 4)), d.spansFor("abcd"))
    }

    @Test
    fun normalizeUrl() {
        assertEquals("https://max.ru", FormatDraft.normalizeUrl("  max.ru "))
        assertEquals("http://a.ru/x", FormatDraft.normalizeUrl("http://a.ru/x"))
        assertEquals("mailto:a@b.ru", FormatDraft.normalizeUrl("mailto:a@b.ru"))
        assertNull(FormatDraft.normalizeUrl("  "))
        assertNull(FormatDraft.normalizeUrl("a b.ru"))
    }

    @Test
    fun coversAcrossNeighbours() {
        val spans = listOf(bold(0, 3), bold(3, 3), span(EMPHASIZED, 0, 10))
        assertTrue(FormatDraft.covers(spans, STRONG, 1, 6))
        assertFalse(FormatDraft.covers(spans, STRONG, 1, 7))
        assertFalse(FormatDraft.covers(listOf(bold(0, 2), bold(3, 2)), STRONG, 0, 5))
    }
}
