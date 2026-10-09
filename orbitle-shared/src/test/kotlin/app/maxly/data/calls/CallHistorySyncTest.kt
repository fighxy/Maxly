package app.maxly.data.calls

import app.maxly.data.CoreCallRepository
import app.maxly.domain.CallOutcome
import com.max.core.calls.CallEnd
import com.max.core.calls.CallHistoryAction
import com.max.core.calls.CallHistoryItem
import com.max.core.calls.CallHistoryPage
import com.max.core.calls.CallMedia
import com.max.core.calls.GroupCallKind
import com.max.core.state.MaxState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallHistorySyncTest {
    private fun item(
        historyId: Long,
        time: Long = historyId * 1_000,
        caller: Long = 7,
        end: CallEnd? = CallEnd.HUNGUP,
        duration: Long? = 30_000,
        messageId: Long? = historyId + 100,
        group: GroupCallKind? = null,
        chatId: Long = 0,
    ) = CallHistoryItem(historyId, "call$historyId", null, caller, messageId, chatId, CallMedia.AUDIO, end, null, time, duration, group)

    @Test
    fun firstPageAndResetReplaceTheLog() {
        val first = CallHistorySync.page(CallHistoryLog(), CallHistoryPage(listOf(item(1), item(2)), sync = 10, reset = false))
        assertTrue(first.loaded)
        assertEquals(10L, first.sync)
        assertEquals(listOf(2L, 1L), first.items.map { it.historyId })
        val reset = CallHistorySync.page(first, CallHistoryPage(listOf(item(5)), sync = 20, reset = true))
        assertEquals(listOf(5L), reset.items.map { it.historyId })
    }

    @Test
    fun deltaPageAddsAndReplacesByHistoryId() {
        val log = CallHistorySync.page(CallHistoryLog(), CallHistoryPage(listOf(item(1), item(2)), 10, false))
        val next = CallHistorySync.page(log, CallHistoryPage(listOf(item(2, duration = 5), item(3)), 11, false))
        assertEquals(listOf(3L, 2L, 1L), next.items.map { it.historyId })
        assertEquals(5L, next.items[1].durationMs)
        assertEquals(11L, next.sync)
    }

    @Test
    fun pushAddsAndRemovesWhenTheCursorMatches() {
        val log = CallHistorySync.page(CallHistoryLog(), CallHistoryPage(listOf(item(1), item(2)), 10, false))
        val added = CallHistorySync.push(log, 11, 10, CallHistoryAction.ADD, listOf(item(3)), emptyList())
        assertFalse(added.resync)
        assertEquals(listOf(3L, 2L, 1L), added.log.items.map { it.historyId })
        assertEquals(11L, added.log.sync)
        val removed = CallHistorySync.push(added.log, 12, 11, CallHistoryAction.REMOVE, emptyList(), listOf(2L))
        assertEquals(listOf(3L, 1L), removed.log.items.map { it.historyId })
    }

    @Test
    fun pushAsksForResyncOnGapUnknownActionOrUnloadedLog() {
        val log = CallHistorySync.page(CallHistoryLog(), CallHistoryPage(listOf(item(1)), 10, false))
        assertTrue(CallHistorySync.push(log, 12, 11, CallHistoryAction.ADD, listOf(item(3)), emptyList()).resync)
        assertTrue(CallHistorySync.push(log, 11, 10, null, emptyList(), emptyList()).resync)
        val idle = CallHistorySync.push(CallHistoryLog(), 1, 0, CallHistoryAction.ADD, listOf(item(3)), emptyList())
        assertTrue(idle.resync)
        assertEquals(CallHistoryLog(), idle.log)
    }

    @Test
    fun withoutDropsByRecordId() {
        val log = CallHistorySync.page(CallHistoryLog(), CallHistoryPage(listOf(item(1), item(2, messageId = null)), 10, false))
        assertEquals(listOf("101"), CallHistorySync.without(log, setOf("h2")).items.map { CallHistoryRecords.id(it) })
    }

    @Test
    fun outcomesAndUnknownDuration() {
        val me = 1L
        val state = MaxState(me = me)
        assertEquals(CallOutcome.MISSED, CoreCallRepository.item(item(1, end = CallEnd.MISSED), me, state).outcome)
        assertEquals(CallOutcome.MISSED, CoreCallRepository.item(item(1, end = CallEnd.HUNGUP, duration = 0), me, state).outcome)
        assertEquals(CallOutcome.ANSWERED, CoreCallRepository.item(item(1, duration = null), me, state).outcome)
        assertEquals(-1L, CoreCallRepository.item(item(1, duration = null), me, state).durationMs)
        val mine = CoreCallRepository.item(item(1, caller = me, end = CallEnd.REJECTED), me, state)
        assertTrue(mine.outgoing)
        assertEquals(CallOutcome.DECLINED, mine.outcome)
        assertEquals(CallOutcome.CANCELLED, CoreCallRepository.item(item(1, caller = me, end = CallEnd.CANCELED), me, state).outcome)
        val group = CoreCallRepository.item(item(4, group = GroupCallKind.LINK, chatId = 0), me, state)
        assertTrue(group.isGroup)
        assertEquals("Групповой звонок", group.title)
        assertEquals("104", group.id)
    }
}
