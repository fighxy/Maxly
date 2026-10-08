package app.orbitle.presentation.calls

import app.orbitle.data.calls.CallControl
import app.orbitle.data.calls.CallEngine
import app.orbitle.data.calls.CallService
import app.orbitle.domain.CallConnection
import app.orbitle.domain.CallEndReason
import app.orbitle.domain.CallLinkPreview
import app.orbitle.domain.CallParticipant
import app.orbitle.domain.CallPhase
import app.orbitle.domain.CallRole
import app.orbitle.domain.CallState
import app.orbitle.domain.CallTopology
import app.orbitle.domain.IncomingCall
import app.orbitle.domain.OrbitleError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeControl(val role: CallRole) : CallControl {
    override val state = MutableStateFlow(CallState(phase = if (role == CallRole.CALLEE) CallPhase.Ringing else CallPhase.Connecting))
    var started = 0
    var accepted: Boolean? = null
    var hungUp = 0
    var camera = false

    override suspend fun start() {
        started++
    }

    override suspend fun accept(video: Boolean) {
        accepted = video
        state.value = state.value.copy(phase = CallPhase.Connecting)
    }

    override suspend fun hangUp() {
        hungUp++
        val reason = if (role == CallRole.CALLEE && accepted == null) CallEndReason.Rejected else CallEndReason.HungUp
        state.value = state.value.copy(phase = CallPhase.Ended(reason))
    }

    override suspend fun setMuted(muted: Boolean) {
        state.value = state.value.copy(muted = muted)
    }

    override suspend fun setCamera(on: Boolean) {
        camera = on
        state.value = state.value.copy(cameraOn = on)
    }

    override suspend fun switchCamera() = Unit
    override suspend fun setScreenSharing(on: Boolean) = Unit
    override fun setSpeaker(on: Boolean) {
        state.value = state.value.copy(speakerOn = on)
    }

    override suspend fun setRecording(on: Boolean) = Unit
    override suspend fun invite(userIds: List<String>) = Unit
    override fun dismissNotice() = Unit
}

private class FakeService : CallService {
    val incoming = MutableSharedFlow<IncomingCall>()
    var failStart: Exception? = null
    var startGate: CompletableDeferred<Unit>? = null
    val started = mutableListOf<Pair<String, Boolean>>()

    override suspend fun startCall(peerId: String, isVideo: Boolean): CallConnection {
        started += peerId to isVideo
        startGate?.await()
        failStart?.let { throw it }
        return CallConnection("conv-$peerId", "wss://x", 1)
    }

    override suspend fun join(link: String, isVideo: Boolean) = CallConnection("group", "wss://x", 1, joinLink = "https://max.ru/joincall/abc")

    override suspend fun createLink() = "https://max.ru/joincall/new"

    override suspend fun preview(link: String) = CallLinkPreview("https://max.ru/joincall/abc", "Планёрка", 3)

    override fun incomingCalls(): Flow<IncomingCall> = incoming
}

@OptIn(ExperimentalCoroutinesApi::class)
class CallCenterTest {
    private val service = FakeService()
    private val controls = mutableListOf<FakeControl>()
    /** Чем движок падает при создании звонка (нет WebRTC, нет камеры…). */
    private var engineFailure: Throwable? = null
    private val engine = CallEngine { _, role, _, _ ->
        engineFailure?.let { throw it }
        FakeControl(role).also { controls += it }
    }

    private fun TestScope.center() = CallCenter(
        service, engine, backgroundScope,
        lookup = { CallPeerInfo(it, "Найден $it") },
        endedDisplayMs = 1_000,
        now = { 1_000_000L },
    )

    @Test
    fun outgoingCallRunsAndEnds() = runTest {
        val center = center()
        var ended = 0
        center.onCallEnded = { ended++ }
        center.startCall(CallPeerInfo("7", "Анна"), video = true)
        runCurrent()
        val call = center.state.value.call!!
        assertEquals(ActiveCall.Direction.OUTGOING, call.direction)
        assertEquals("conv-7", call.conversationId)
        val control = controls.single()
        assertEquals(1, control.started)
        assertTrue(control.camera)

        control.state.value = control.state.value.copy(phase = CallPhase.Ringing)
        runCurrent()
        assertTrue(center.state.value.playsRingback)

        center.toggleMute()
        runCurrent()
        assertTrue(center.state.value.call!!.state.muted)
        center.hangUp()
        runCurrent()
        assertEquals(1, ended)
        assertTrue(center.state.value.call!!.state.isEnded)
        advanceTimeBy(1_100)
        runCurrent()
        assertNull(center.state.value.call)
    }

    @Test
    fun failedStartShowsError() = runTest {
        val center = center()
        service.failStart = OrbitleError.NetworkUnavailable
        center.startCall(CallPeerInfo("7", "Анна"), video = false)
        assertNull(center.state.value.call)
        assertEquals("Нет соединения с сервером", center.state.value.errorMessage)
    }

    @Test
    fun hangUpBeforeServerAnswersCancelsTheCall() = runTest {
        val center = center()
        service.startGate = CompletableDeferred()
        val job = backgroundScope.launch { center.startCall(CallPeerInfo("7", "Анна"), video = false) }
        runCurrent()
        center.hangUp()
        runCurrent()
        assertTrue(center.state.value.call!!.state.isEnded)
        service.startGate!!.complete(Unit)
        job.join()
        // Сервер успел начать звонок: его сразу кладут.
        assertEquals(1, controls.single().hungUp)
    }

    @Test
    fun incomingIsAnsweredOrDeclined() = runTest {
        val center = center()
        center.activate()
        runCurrent()
        val connection = CallConnection("in", "wss://x", 1)
        service.incoming.emit(IncomingCall("in", "9", "", isVideo = true, connection = connection))
        runCurrent()
        val call = center.state.value.call!!
        assertTrue(call.isRinging)
        // Имени не было: его нашли.
        assertEquals("Найден 9", call.peer.name)
        center.answer(video = true)
        runCurrent()
        assertEquals(true, controls.single().accepted)
        assertFalse(center.state.value.call!!.isRinging)
        center.hangUp()
        advanceTimeBy(1_100)
        runCurrent()

        // Второй входящий отклоняют.
        service.incoming.emit(IncomingCall("in2", "9", "Иван", isVideo = false, connection = connection))
        runCurrent()
        center.decline()
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.Rejected), center.state.value.call!!.state.phase)
    }

    @Test
    fun busyAndExpiredIncomingAreIgnored() = runTest {
        val center = center()
        center.activate()
        runCurrent()
        val connection = CallConnection("in", "wss://x", 1)
        service.incoming.emit(IncomingCall("old", "9", "Иван", isVideo = false, connection = connection, expiresAtMs = 999_999L))
        runCurrent()
        assertNull(center.state.value.call)
        center.startCall(CallPeerInfo("7", "Анна"), video = false)
        service.incoming.emit(IncomingCall("in", "9", "Иван", isVideo = false, connection = connection))
        runCurrent()
        assertEquals("conv-7", center.state.value.call!!.conversationId)
        assertEquals(1, controls.size)
        center.startCall(CallPeerInfo("8", "Борис"), video = false)
        assertEquals("Сначала закончите текущий звонок", center.state.value.errorMessage)
    }

    @Test
    fun joinsGroupByLinkWithItsName() = runTest {
        val center = center()
        center.join("https://max.ru/joincall/abc")
        val call = center.state.value.call!!
        assertEquals(ActiveCall.Direction.GROUP, call.direction)
        assertEquals("Планёрка", call.peer.name)
        assertEquals("https://max.ru/joincall/abc", call.joinLink)
        assertEquals(CallRole.JOINER, controls.single().role)
        controls.single().state.value = CallState(participants = listOf(CallParticipant(5, userId = "55")))
        runCurrent()
        assertEquals("Найден 55", center.state.value.name("55"))
        assertEquals("https://max.ru/joincall/new", center.createLink())
    }

    @Test
    fun statusTexts() {
        val base = ActiveCall("1", "c", ActiveCall.Direction.OUTGOING, CallPeerInfo("7", "Анна"), false, state = CallState(), answered = true)
        assertEquals("Соединение…", CallStatusText.status(base, 0))
        assertEquals("Вызов…", CallStatusText.status(base.copy(state = CallState(phase = CallPhase.Ringing)), 0))
        val incoming = base.copy(direction = ActiveCall.Direction.INCOMING, isVideo = true, answered = false, state = CallState(phase = CallPhase.Ringing))
        assertEquals("Входящий видеозвонок", CallStatusText.status(incoming, 0))
        val active = base.copy(state = CallState(phase = CallPhase.Active, activeSinceMs = 0, mediaConnected = true))
        assertEquals("1:05", CallStatusText.status(active, 65_000))
        val group = base.copy(
            direction = ActiveCall.Direction.GROUP,
            state = CallState(phase = CallPhase.Active, activeSinceMs = 0, topology = CallTopology.SERVER, participants = List(3) { CallParticipant(it.toLong()) }),
        )
        assertEquals("1:02:03 · 3 участника", CallStatusText.status(group, 3_723_000))
        assertEquals("Абонент занят", CallStatusText.ended(CallEndReason.Busy))
        assertEquals("21 участник", CallStatusText.participants(21))
        assertEquals("11 участников", CallStatusText.participants(11))
    }

    @Test
    fun incomingCallThatTheEngineCannotTakeIsDroppedWithoutCrashing() = runTest {
        val center = center()
        center.activate()
        runCurrent()
        engineFailure = IllegalStateException("createPeerConnectionFactory")
        val connection = CallConnection("in", "wss://x", 1)
        service.incoming.emit(IncomingCall("in", "9", "Иван", isVideo = false, connection = connection))
        runCurrent()
        assertNull(center.state.value.call)
        assertEquals("Не удалось принять звонок", center.state.value.errorMessage)

        // Подписка на входящие жива: следующий звонок приходит как обычно.
        engineFailure = null
        service.incoming.emit(IncomingCall("in2", "9", "Иван", isVideo = false, connection = connection))
        runCurrent()
        assertTrue(center.state.value.call!!.isRinging)
        assertEquals(1, controls.single().started)
    }

    @Test
    fun missingNativeLibraryFailsTheCallInsteadOfCrashing() = runTest {
        val center = center()
        engineFailure = UnsatisfiedLinkError("dlopen failed: libjingle_peerconnection_so.so")
        center.startCall(CallPeerInfo("7", "Анна"), video = false)
        runCurrent()
        assertNull(center.state.value.call)
        assertEquals("Не удалось позвонить", center.state.value.errorMessage)
    }
}
