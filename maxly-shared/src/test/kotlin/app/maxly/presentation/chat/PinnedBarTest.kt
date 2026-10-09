package app.maxly.presentation.chat

import app.maxly.domain.ChatType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PinnedBarTest {
    private fun bar(vararg ids: String) = PinnedBar(ids.map { PinnedEntry(it, "т$it") })

    @Test
    fun emptyBarShowsNothing() {
        val empty = PinnedBar()
        assertNull(empty.current)
        assertEquals(0, empty.count)
        assertEquals(empty, empty.next())
    }

    @Test
    fun singlePinHasPlainTitleAndStays() {
        val one = bar("5")
        assertEquals("Закреплённое сообщение", one.title)
        assertEquals("5", one.next().current?.messageId)
    }

    @Test
    fun cyclesThroughAllAndWrapsAround() {
        var b = bar("3", "2", "1")
        assertEquals("Закреплённое сообщение 1 из 3", b.title)
        b = b.next()
        assertEquals("2", b.current?.messageId)
        assertEquals("Закреплённое сообщение 2 из 3", b.title)
        b = b.next().next()
        assertEquals("3", b.current?.messageId)
    }

    @Test
    fun replaceKeepsShownPinWhenStillPinned() {
        val shown = bar("3", "2", "1").next()
        val updated = shown.replace(listOf(PinnedEntry("4", "т4"), PinnedEntry("3", "т3"), PinnedEntry("2", "т2")))
        assertEquals("2", updated.current?.messageId)
        assertEquals(2, updated.index)
    }

    @Test
    fun replaceFallsBackToNewestWhenShownWasUnpinned() {
        val shown = bar("3", "2", "1").next()
        assertEquals("3", shown.replace(listOf(PinnedEntry("3", "т3"), PinnedEntry("1", "т1"))).current?.messageId)
    }

    @Test
    fun withoutDropsOnlyThatMessage() {
        val b = bar("3", "2").without("3")
        assertEquals(listOf("2"), b.entries.map { it.messageId })
        assertTrue("2" in b)
        assertFalse("3" in b)
    }

    @Test
    fun choicesDependOnChatKind() {
        assertEquals(listOf("Закрепить"), PinChoices.of(ChatType.PRIVATE, savedMessages = true).map { it.label })
        val dialog = PinChoices.of(ChatType.PRIVATE, savedMessages = false)
        assertEquals(listOf(false, true), dialog.map { it.forMe })
        assertTrue(dialog.all { it.notify })
        val group = PinChoices.of(ChatType.GROUP, savedMessages = false)
        assertEquals(listOf(true, false), group.map { it.notify })
        assertTrue(group.none { it.forMe })
    }

    @Test
    fun attachmentFailureTargetsOnlyALoneUpload() {
        assertEquals("local-1", AttachmentFailures.target(listOf("local-1")))
        assertNull(AttachmentFailures.target(emptyList()))
        assertNull(AttachmentFailures.target(listOf("local-1", "local-2")))
        // С id вложения загрузку обрывает само ядро.
        assertNull(AttachmentFailures.target(listOf("local-1"), uploadId = 77L))
    }

    @Test
    fun attachmentFailureTextCarriesServerReason() {
        assertEquals("Вложение не отправлено: file.type.forbidden", AttachmentFailures.text("file.type.forbidden"))
        assertEquals("Вложение не отправлено: Файл слишком большой", AttachmentFailures.text("  Файл слишком большой "))
        assertEquals("Вложение не отправлено", AttachmentFailures.text(null))
        assertEquals("Вложение не отправлено", AttachmentFailures.text(" "))
    }
}
