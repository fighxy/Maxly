package app.orbitle.platform

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class WindowActivityTest {
    private fun TestScope.activity() = WindowActivity(clock = { testScheduler.currentTime })

    /** Все значения потока по порядку. */
    private fun TestScope.record(flow: kotlinx.coroutines.flow.Flow<Boolean>): MutableList<Boolean> {
        val values = mutableListOf<Boolean>()
        backgroundScope.launch { flow.collect { values += it } }
        runCurrent()
        return values
    }

    @Test
    fun looksOnlyAtAVisibleFocusedWindow() {
        assertTrue(WindowActivity.isLooking(minimized = false, focused = true))
        assertFalse(WindowActivity.isLooking(minimized = false, focused = false))
        assertFalse(WindowActivity.isLooking(minimized = true, focused = true))
        assertFalse(WindowActivity.isLooking(minimized = true, focused = false))
    }

    @Test
    fun focusAndMinimizeDriveLookingAndShown() = runTest {
        val window = activity()
        val looking = record(window.looking)
        assertEquals(listOf(false), looking)
        window.setFocused(true)
        runCurrent()
        window.setMinimized(true)
        runCurrent()
        assertFalse(window.shown.value)
        window.setMinimized(false)
        runCurrent()
        assertTrue(window.shown.value)
        window.setFocused(false)
        runCurrent()
        assertEquals(listOf(false, true, false, true, false), looking)
    }

    @Test
    fun activeAfterFocusAndIdleAfterAMinuteWithoutInput() = runTest {
        val window = activity()
        val active = record(window.active)
        assertEquals(listOf(false), active)
        window.setFocused(true)
        runCurrent()
        assertEquals(listOf(false, true), active)
        advanceTimeBy(WindowActivity.IDLE_MS - 1)
        runCurrent()
        assertEquals(listOf(false, true), active)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf(false, true, false), active)
        // Ввод возвращает активность и начинает отсчёт заново.
        window.input()
        runCurrent()
        assertEquals(listOf(false, true, false, true), active)
        advanceTimeBy(30_000)
        window.input()
        runCurrent()
        advanceTimeBy(WindowActivity.IDLE_MS - 1)
        runCurrent()
        assertEquals(listOf(false, true, false, true), active)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf(false, true, false, true, false), active)
    }

    @Test
    fun inputDoesNotMakeAMinimizedOrUnfocusedWindowActive() = runTest {
        val window = activity()
        val active = record(window.active)
        window.input()
        runCurrent()
        assertEquals(listOf(false), active)
        window.setFocused(true)
        window.setMinimized(true)
        runCurrent()
        window.input()
        runCurrent()
        assertEquals(false, active.last())
        window.setMinimized(false)
        runCurrent()
        assertEquals(true, active.last())
        window.setFocused(false)
        runCurrent()
        assertEquals(false, active.last())
    }
}
