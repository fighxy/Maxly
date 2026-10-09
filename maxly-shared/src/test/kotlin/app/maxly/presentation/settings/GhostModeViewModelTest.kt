package app.maxly.presentation.settings

import app.maxly.MainDispatcherRule
import app.maxly.data.GhostModeRepository
import app.maxly.data.OwnPresenceSettings
import app.maxly.data.PeerPresence
import app.maxly.data.PreferenceStore
import app.maxly.presentation.common.PresenceText
import app.maxly.presentation.settings.GhostModeViewModel.Toggle
import com.maxly.core.api.PresenceStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.ZoneOffset

/** Опрос идёт на тестовом диспетчере: время двигает [tick], часы модели — его же. */
@OptIn(ExperimentalCoroutinesApi::class)
class GhostModeViewModelTest {
    @get:Rule val main = MainDispatcherRule(StandardTestDispatcher())

    private class MapStore(val values: MutableMap<String, String> = mutableMapOf()) : PreferenceStore {
        override fun get(key: String) = values[key]
        override fun put(key: String, value: String) {
            values[key] = value
        }
    }

    /** Ядро понарошку: флаги, счётчик проверок и ответ на следующую. */
    private class FakeGhost : GhostModeRepository {
        override val ghostMode = MutableStateFlow(false)
        override val hideReadReceipts = MutableStateFlow(false)
        var checks = 0
        var answer: PeerPresence? = null
        var failure: Exception? = null
        var gate: CompletableDeferred<Unit>? = null

        override fun setGhostMode(enabled: Boolean) {
            ghostMode.value = enabled
        }

        override fun setHideReadReceipts(enabled: Boolean) {
            hideReadReceipts.value = enabled
        }

        override suspend fun checkOwnPresence(): PeerPresence? {
            checks++
            gate?.await()
            failure?.let { throw it }
            return answer
        }
    }

    /** 2026-10-08 15:00 UTC. */
    private val base = 1_791_471_600_000L
    private val scheduler get() = main.dispatcher.scheduler
    private val store = MapStore()
    private val ghost = FakeGhost()
    private val foreground = MutableStateFlow(true)
    private val poll = GhostModeViewModel.POLL_MS
    private val online = PeerPresence(isOnline = true, lastSeenMs = base, presence = PresenceStatus.ONLINE)

    private fun model(merge: Boolean = false) = GhostModeViewModel(
        ghost,
        OwnPresenceSettings(store),
        foreground = foreground,
        mergeReadReceipts = merge,
        now = { base + scheduler.currentTime },
        presence = PresenceText(ZoneOffset.UTC),
    ).also { scheduler.runCurrent() }

    private fun tick(ms: Long) {
        scheduler.advanceTimeBy(ms)
        scheduler.runCurrent()
    }

    @Test
    fun `switches start from what is stored and own presence is on by default`() {
        ghost.ghostMode.value = true
        val m = model()
        assertTrue(m.state.value.isOn(Toggle.GHOST))
        assertFalse(m.state.value.isOn(Toggle.READ_RECEIPTS))
        assertTrue(m.state.value.isOn(Toggle.OWN_PRESENCE))
        assertEquals(listOf(Toggle.GHOST, Toggle.READ_RECEIPTS, Toggle.OWN_PRESENCE), m.state.value.toggles)
    }

    @Test
    fun `toggles go to their own flags and follow core events`() {
        val m = model()
        m.set(Toggle.READ_RECEIPTS, true)
        scheduler.runCurrent()
        assertTrue(ghost.hideReadReceipts.value)
        assertFalse(ghost.ghostMode.value)
        m.set(Toggle.GHOST, true)
        scheduler.runCurrent()
        assertTrue(m.state.value.ghostMode)
        // Событие ядра: флаг сменился не отсюда.
        ghost.hideReadReceipts.value = false
        scheduler.runCurrent()
        assertFalse(m.state.value.isOn(Toggle.READ_RECEIPTS))
        m.set(Toggle.OWN_PRESENCE, false)
        scheduler.runCurrent()
        assertEquals("false", store.values[OwnPresenceSettings.KEY_SHOWN])
        assertFalse(m.state.value.showOwnPresence)
    }

    @Test
    fun `merged ghost switch drives both flags and hides the read receipts row`() {
        val m = model(merge = true)
        assertEquals(listOf(Toggle.GHOST, Toggle.OWN_PRESENCE), m.state.value.toggles)
        m.set(Toggle.GHOST, true)
        scheduler.runCurrent()
        assertTrue(ghost.ghostMode.value)
        assertTrue(ghost.hideReadReceipts.value)
        assertTrue(m.state.value.isOn(Toggle.GHOST))
        // Только половина включена (например, до объединения): переключатель выключен.
        ghost.hideReadReceipts.value = false
        scheduler.runCurrent()
        assertFalse(m.state.value.isOn(Toggle.GHOST))
        m.set(Toggle.GHOST, false)
        scheduler.runCurrent()
        assertFalse(ghost.ghostMode.value)
    }

    @Test
    fun `own status is polled once a minute by default`() {
        assertEquals(60_000L, GhostModeViewModel.POLL_MS)
    }

    @Test
    fun `nothing is asked until the profile is visible`() {
        val m = model()
        tick(2 * poll)
        assertEquals(0, ghost.checks)
        assertNull(m.state.value.ownLine)
    }

    @Test
    fun `visible profile asks at once and then once a minute`() {
        ghost.answer = online
        val m = model()
        m.setProfileVisible(true)
        scheduler.runCurrent()
        assertEquals(1, ghost.checks)
        assertEquals("в сети", m.state.value.ownLine)
        tick(poll - 1)
        assertEquals(1, ghost.checks)
        tick(1)
        assertEquals(2, ghost.checks)
        tick(poll)
        assertEquals(3, ghost.checks)
    }

    @Test
    fun `leaving the profile or going to background stops polling, return asks at once`() {
        ghost.answer = online
        val m = model()
        m.setProfileVisible(true)
        tick(5_000)
        assertEquals(1, ghost.checks)
        foreground.value = false
        tick(2 * poll)
        assertEquals(1, ghost.checks)
        foreground.value = true
        scheduler.runCurrent()
        assertEquals(2, ghost.checks)
        m.setProfileVisible(false)
        tick(2 * poll)
        assertEquals(2, ghost.checks)
        m.setProfileVisible(true)
        scheduler.runCurrent()
        assertEquals(3, ghost.checks)
        // Отсчёт начался с возврата.
        tick(poll)
        assertEquals(4, ghost.checks)
    }

    @Test
    fun `ghost toggle and refresh ask at once and restart the countdown`() {
        ghost.answer = online
        val m = model()
        m.setProfileVisible(true)
        tick(10_000)
        assertEquals(1, ghost.checks)
        m.set(Toggle.GHOST, true)
        scheduler.runCurrent()
        assertEquals(2, ghost.checks)
        tick(10_000)
        m.refreshOwnPresence()
        scheduler.runCurrent()
        assertEquals(3, ghost.checks)
        tick(poll - 1)
        assertEquals(3, ghost.checks)
        tick(1)
        assertEquals(4, ghost.checks)
        // Отметки о прочтении на свой статус не влияют: внеочередного запроса нет.
        m.set(Toggle.READ_RECEIPTS, true)
        scheduler.runCurrent()
        assertEquals(4, ghost.checks)
    }

    @Test
    fun `own presence off stops polling and forgets the status`() {
        ghost.answer = online
        val m = model()
        m.setProfileVisible(true)
        scheduler.runCurrent()
        m.set(Toggle.OWN_PRESENCE, false)
        tick(2 * poll)
        assertEquals(1, ghost.checks)
        assertNull(m.state.value.own)
        assertNull(m.state.value.ownLine)
        m.set(Toggle.OWN_PRESENCE, true)
        scheduler.runCurrent()
        assertEquals(2, ghost.checks)
        assertEquals("в сети", m.state.value.ownLine)
    }

    @Test
    fun `last seen uses the shared presence wording, no time reads as offline`() {
        val m = model()
        ghost.answer = PeerPresence(isOnline = false, lastSeenMs = base - 2 * 3_600_000L - 25 * 60_000L, presence = PresenceStatus.OFFLINE)
        m.setProfileVisible(true)
        scheduler.runCurrent()
        assertEquals("был(а) в 12:35", m.state.value.ownLine)
        ghost.answer = PeerPresence(isOnline = false, lastSeenMs = base + poll, presence = PresenceStatus.OFFLINE)
        tick(poll)
        assertEquals("был(а) только что", m.state.value.ownLine)
        tick(poll)
        // Тот же ответ сервера стареет вместе с часами.
        assertEquals("был(а) 1 минуту назад", m.state.value.ownLine)
        ghost.answer = PeerPresence(isOnline = false, lastSeenMs = 0, presence = PresenceStatus.RECENTLY)
        tick(poll)
        assertEquals("был(а) недавно", m.state.value.ownLine)
        ghost.answer = PeerPresence(isOnline = false, lastSeenMs = 0, presence = PresenceStatus.UNKNOWN)
        tick(poll)
        assertEquals(GhostModeViewModel.OFFLINE, m.state.value.ownLine)
    }

    @Test
    fun `no answer or a failure hides the line until the next good poll`() {
        val m = model()
        m.setProfileVisible(true)
        scheduler.runCurrent()
        assertNull(m.state.value.ownLine)
        ghost.answer = online
        tick(poll)
        assertEquals("в сети", m.state.value.ownLine)
        ghost.failure = IllegalStateException("нет связи")
        tick(poll)
        assertNull(m.state.value.ownLine)
        ghost.failure = null
        tick(poll)
        assertEquals("в сети", m.state.value.ownLine)
    }

    @Test
    fun `a slow check is dropped when the profile goes away`() {
        val gate = CompletableDeferred<Unit>()
        ghost.gate = gate
        ghost.answer = online
        val m = model()
        m.setProfileVisible(true)
        scheduler.runCurrent()
        assertTrue(m.state.value.checking)
        m.setProfileVisible(false)
        scheduler.runCurrent()
        gate.complete(Unit)
        scheduler.runCurrent()
        assertFalse(m.state.value.checking)
        assertNull(m.state.value.own)
        assertEquals(1, ghost.checks)
    }
}
