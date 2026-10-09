package app.maxly.presentation.chat

import app.maxly.domain.PollAnswer
import app.maxly.domain.PollContent
import app.maxly.domain.PollTally
import app.maxly.domain.ScheduledChange
import app.maxly.domain.ScheduledMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduledPollsTest {
    private val a = ScheduledMessage("1", "а", 3_000L)
    private val b = ScheduledMessage("2", "б", 1_000L)
    private val noTime = ScheduledMessage("3", "в", null)

    @Test
    fun scheduledSortedBySendTimeWithUnknownLast() {
        assertEquals(listOf("2", "1", "3"), ScheduledList.sorted(listOf(noTime, a, b)).map { it.id })
    }

    @Test
    fun upsertAddsOrReplacesInOrder() {
        val list = ScheduledList.sorted(listOf(a, b))
        val created = ScheduledList.apply(list, ScheduledChange.Upsert(ScheduledMessage("4", "г", 2_000L)))!!
        assertEquals(listOf("2", "4", "1"), created.map { it.id })
        val edited = ScheduledList.apply(created, ScheduledChange.Upsert(a.copy(text = "А", sendAt = 500L)))!!
        assertEquals(listOf("1", "2", "4"), edited.map { it.id })
        assertEquals("А", edited.first().text)
    }

    @Test
    fun deletedAndFiredLeaveTheList() {
        val list = listOf(b, a)
        assertEquals(listOf("1"), ScheduledList.apply(list, ScheduledChange.Removed(listOf("2"), fired = false))!!.map { it.id })
        assertEquals(listOf("2"), ScheduledList.apply(list, ScheduledChange.Removed(listOf("1"), fired = true))!!.map { it.id })
        assertNull(ScheduledList.apply(list, ScheduledChange.Reload))
    }

    private val poll = PollContent("p", "Вопрос", listOf(PollAnswer("1", "Да", 1), PollAnswer("2", "Нет", 0)), total = 1)

    @Test
    fun votingRules() {
        assertTrue(PollRules.canVote(poll))
        assertFalse(PollRules.canVote(poll.copy(mine = setOf("1"))))
        assertTrue(PollRules.canVote(poll.copy(mine = setOf("1"), revote = true)))
        assertFalse(PollRules.canVote(poll.copy(closed = true)))
    }

    @Test
    fun toggleSingleAndMultiple() {
        assertEquals(setOf("2"), PollRules.toggle(poll, setOf("1"), "2"))
        val multi = poll.copy(multiple = true)
        assertEquals(setOf("1", "2"), PollRules.toggle(multi, setOf("1"), "2"))
        assertEquals(setOf("2"), PollRules.toggle(multi, setOf("1", "2"), "1"))
    }

    @Test
    fun tallyUpdatesCountsAndKeepsMissingRows() {
        val next = PollRules.applyTally(poll, PollTally(4, mapOf("2" to 3)))
        assertEquals(4, next.total)
        assertEquals(listOf(1, 3), next.answers.map { it.votes })
    }

    @Test
    fun mergeTakesFreshStateAndOwnVote() {
        val fresh = poll.copy(title = "", total = 9, closed = true)
        val merged = PollRules.merge(poll, fresh, setOf("2"), null)
        assertEquals("Вопрос", merged.title)
        assertEquals(9, merged.total)
        assertTrue(merged.closed)
        assertEquals(setOf("2"), merged.mine)
        assertEquals(poll, PollRules.merge(poll, null, null, null))
    }

    @Test
    fun footerText() {
        assertEquals("Голосов: 1", PollRules.footer(poll))
        assertEquals("Голосов: 1 · можно выбрать несколько", PollRules.footer(poll.copy(multiple = true)))
        assertEquals("Голосов: 1 · опрос завершён", PollRules.footer(poll.copy(closed = true, multiple = true)))
    }
}
