package app.maxly.presentation.common

import app.maxly.domain.CallEndReason
import app.maxly.domain.CallPhase
import app.maxly.domain.CallState
import app.maxly.presentation.calls.ActiveCall
import app.maxly.presentation.calls.CallCenterState
import app.maxly.presentation.calls.CallPeerInfo
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppActivityTest {
    private fun call(direction: ActiveCall.Direction, phase: CallPhase, answered: Boolean = false) = CallCenterState(
        ActiveCall("1", "c", direction, CallPeerInfo("2", "Анна"), isVideo = false, state = CallState(phase = phase), answered = answered),
    )

    @Test
    fun `foreground with an unlocked screen is active`() {
        assertTrue(AppActivity.android(foreground = true, unlocked = true, inCall = false))
        assertFalse(AppActivity.android(foreground = true, unlocked = false, inCall = false))
        assertFalse(AppActivity.android(foreground = false, unlocked = true, inCall = false))
    }

    @Test
    fun `an ongoing call keeps the app active in the background`() {
        assertTrue(AppActivity.android(foreground = false, unlocked = false, inCall = true))
        assertFalse(AppActivity.inCall(CallCenterState()))
        assertTrue(AppActivity.inCall(call(ActiveCall.Direction.OUTGOING, CallPhase.Ringing)))
        assertTrue(AppActivity.inCall(call(ActiveCall.Direction.INCOMING, CallPhase.Active, answered = true)))
        // Входящий, который ещё звонит, и завершённый — не разговор.
        assertFalse(AppActivity.inCall(call(ActiveCall.Direction.INCOMING, CallPhase.Ringing)))
        assertFalse(AppActivity.inCall(call(ActiveCall.Direction.OUTGOING, CallPhase.Ended(CallEndReason.HungUp))))
    }

    @Test
    fun `desktop stays active during a call even when the window is not`() {
        assertTrue(AppActivity.desktop(windowActive = true, inCall = false))
        assertFalse(AppActivity.desktop(windowActive = false, inCall = false))
        // Окно свёрнуто или без фокуса, но идёт разговор: флаг не гаснет.
        assertTrue(AppActivity.desktop(windowActive = false, inCall = true))
    }

    @Test
    fun `every change is reported once, the first one at once`() = runTest {
        val active = MutableStateFlow(false)
        val sent = mutableListOf<Boolean>()
        val job = AppActivity.report(backgroundScope, active) { sent += it }
        testScheduler.runCurrent()
        assertEquals(listOf(false), sent)
        active.value = true
        testScheduler.runCurrent()
        active.value = true
        testScheduler.runCurrent()
        active.value = false
        testScheduler.runCurrent()
        assertEquals(listOf(false, true, false), sent)
        job.cancel()
    }
}
