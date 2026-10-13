package app.maxly.presentation.chat

import app.maxly.domain.VideoNoteRecording
import app.maxly.domain.VoiceRecording
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeRecorder : ComposerRecorder {
    var access = ComposerRecorder.Access.GRANTED
    var startOk = true
    val log = mutableListOf<String>()
    override var onLimit: (() -> Unit)? = null

    override fun access(mode: RecordingMode) = access
    override suspend fun requestAccess(mode: RecordingMode): Boolean {
        log += "ask $mode"
        return true
    }

    override suspend fun start(mode: RecordingMode): Boolean {
        log += "start $mode"
        return startOk
    }

    override suspend fun stop(mode: RecordingMode): RecordedDraft {
        log += "stop $mode"
        return if (mode == RecordingMode.VOICE) RecordedDraft.Voice(VoiceRecording("/v.ogg", 2_000, listOf(1)))
        else RecordedDraft.Note(VideoNoteRecording("/n.mp4", 3_000, 480))
    }

    override suspend fun cancel(mode: RecordingMode) {
        log += "cancel $mode"
    }

    override suspend fun trim(recording: VideoNoteRecording, fromMs: Long, toMs: Long): VideoNoteRecording {
        log += "trim $fromMs-$toMs"
        return VideoNoteRecording("/t.mp4", toMs - fromMs, recording.side)
    }

    override suspend fun discard(recording: VideoNoteRecording) {
        log += "discard ${recording.path}"
    }

    override fun setPaused(mode: RecordingMode, paused: Boolean): Boolean {
        log += "${if (paused) "pause" else "resume"} $mode"
        return true
    }

    override suspend fun trimVoice(recording: VoiceRecording, fromMs: Long, toMs: Long): VoiceRecording {
        log += "trimVoice $fromMs-$toMs"
        return VoiceRecording("/c.ogg", toMs - fromMs, recording.waveform)
    }

    override suspend fun discardVoice(recording: VoiceRecording) {
        log += "discardVoice ${recording.path}"
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class RecordingControllerTest {
    private val recorder = FakeRecorder()

    private fun TestScope.controller(): Pair<RecordingController, MutableList<RecordedDraft>> {
        val sent = mutableListOf<RecordedDraft>()
        val controller = RecordingController(recorder, backgroundScope)
        controller.onRecorded = { sent += it }
        return controller to sent
    }

    @Test
    fun holdRecordsAndReleaseSends() = runTest {
        val (controller, sent) = controller()
        controller.press()
        runCurrent()
        assertEquals(listOf("start VOICE"), recorder.log)
        assertEquals(RecordingController.Phase.PRESSING, controller.state.value.phase)
        advanceTimeBy(200)
        assertEquals(RecordingController.Phase.RECORDING, controller.state.value.phase)
        controller.move(-30f, 0f)
        assertEquals(-30f, controller.state.value.dragX)
        controller.release()
        runCurrent()
        assertEquals(listOf("start VOICE", "stop VOICE"), recorder.log)
        assertTrue(sent.single() is RecordedDraft.Voice)
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
    }

    @Test
    fun shortMicTapShowsHintAndCameraTapTakesShot() = runTest {
        val (controller, sent) = controller()
        var shots = 0
        controller.onCameraTap = { shots++ }
        controller.press(RecordingMode.VOICE)
        runCurrent()
        controller.release()
        runCurrent()
        assertEquals(listOf("start VOICE", "cancel VOICE"), recorder.log)
        assertEquals(RecordingGesture.HOLD_HINT, controller.state.value.hint)
        assertEquals(0, shots)
        // Касание камеры её не включает: это снимок.
        controller.press(RecordingMode.VIDEO)
        advanceTimeBy(100)
        controller.release()
        runCurrent()
        assertEquals(1, shots)
        assertEquals(listOf("start VOICE", "cancel VOICE"), recorder.log)
        assertTrue(sent.isEmpty())
    }

    @Test
    fun holdingCameraRecordsVideoNote() = runTest {
        val (controller, sent) = controller()
        var shots = 0
        controller.onCameraTap = { shots++ }
        controller.press(RecordingMode.VIDEO)
        advanceTimeBy(200)
        runCurrent()
        assertTrue(recorder.log.isEmpty())
        advanceTimeBy(120)
        runCurrent()
        assertEquals(listOf("start VIDEO"), recorder.log)
        assertEquals(RecordingController.Phase.RECORDING, controller.state.value.phase)
        assertTrue(controller.state.value.owns(RecordingMode.VIDEO))
        controller.release()
        runCurrent()
        assertTrue(sent.single() is RecordedDraft.Note)
        assertEquals(0, shots)
    }

    @Test
    fun swipeLeftCancelsAndUpLocks() = runTest {
        val (controller, sent) = controller()
        controller.press()
        advanceTimeBy(200)
        controller.move(-130f, 0f)
        runCurrent()
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
        assertEquals("cancel VOICE", recorder.log.last())

        controller.press()
        advanceTimeBy(200)
        controller.move(0f, -100f)
        assertEquals(RecordingController.Phase.LOCKED, controller.state.value.phase)
        // Палец, закрепивший запись, отпускается — запись идёт дальше.
        controller.release()
        runCurrent()
        assertEquals(RecordingController.Phase.LOCKED, controller.state.value.phase)
        // Следующее нажатие отправляет.
        controller.release()
        runCurrent()
        assertEquals(1, sent.size)
    }

    @Test
    fun deniedAccessShowsHintAndAskDoesNotRecord() = runTest {
        val (controller, _) = controller()
        recorder.access = ComposerRecorder.Access.DENIED
        controller.press()
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
        assertTrue(controller.state.value.hint!!.contains("микрофону"))
        recorder.access = ComposerRecorder.Access.ASK
        controller.press()
        // Палец отпускается, пока система ещё спрашивает.
        controller.release()
        runCurrent()
        assertEquals(listOf("ask VOICE"), recorder.log)
        // Отпускание после запроса доступа подсказку не показывает.
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
    }

    @Test
    fun failedStartAndInterruptAndLimit() = runTest {
        val (controller, sent) = controller()
        recorder.startOk = false
        controller.press()
        runCurrent()
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
        assertEquals("Не удалось включить микрофон", controller.state.value.hint)

        recorder.startOk = true
        controller.press()
        advanceTimeBy(200)
        controller.interrupt()
        assertEquals(RecordingController.Phase.LOCKED, controller.state.value.phase)
        recorder.onLimit?.invoke()
        runCurrent()
        assertEquals(1, sent.size)
    }

    @Test
    fun keyStartsLockedRecordingAndSendsOnSecondPress() = runTest {
        val (controller, sent) = controller()
        controller.toggleByKey()
        runCurrent()
        assertEquals(RecordingController.Phase.LOCKED, controller.state.value.phase)
        assertEquals(listOf("start VOICE"), recorder.log)
        controller.toggleByKey()
        runCurrent()
        assertEquals(1, sent.size)
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
    }

    @Test
    fun lockedNoteGoesToReviewThenTrimmedPartIsSent() = runTest {
        val (controller, sent) = controller()
        controller.press(RecordingMode.VIDEO)
        advanceTimeBy(300)
        runCurrent()
        controller.move(0f, -100f)
        assertEquals(RecordingController.Phase.LOCKED, controller.state.value.phase)
        controller.release()
        controller.stopForReview()
        runCurrent()
        val review = controller.state.value.review
        assertEquals(RecordingController.Phase.REVIEWING, controller.state.value.phase)
        assertNotNull(review)
        assertTrue(sent.isEmpty())
        // Кусок не короче секунды: ручки не сходятся ближе.
        controller.trim(0.5f, 0.5f)
        val clamped = controller.state.value.review!!
        assertEquals(1_000L, clamped.toMs - clamped.fromMs)
        controller.trim(0.2f, 0.8f)
        controller.release()
        runCurrent()
        assertEquals(listOf("start VIDEO", "stop VIDEO", "trim 600-2400", "discard /n.mp4"), recorder.log)
        assertEquals(1_800L, (sent.single() as RecordedDraft.Note).recording.durationMs)
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
    }

    @Test
    fun reviewTrashDiscardsAndWholeNoteIsSentAsIs() = runTest {
        val (controller, sent) = controller()
        controller.toggleByKey(RecordingMode.VIDEO)
        runCurrent()
        controller.stopForReview()
        runCurrent()
        controller.cancel()
        runCurrent()
        assertEquals("discard /n.mp4", recorder.log.last())
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
        assertTrue(sent.isEmpty())

        controller.toggleByKey(RecordingMode.VIDEO)
        runCurrent()
        controller.stopForReview()
        runCurrent()
        controller.send()
        runCurrent()
        assertEquals("/n.mp4", (sent.single() as RecordedDraft.Note).recording.path)
    }

    @Test
    fun lockedVoicePausesThenGoesToReviewAndTrimmedPartIsSent() = runTest {
        val (controller, sent) = controller()
        controller.toggleByKey(RecordingMode.VOICE)
        runCurrent()
        controller.togglePause()
        assertTrue(controller.state.value.paused)
        controller.togglePause()
        assertTrue(!controller.state.value.paused)
        controller.stopForReview()
        runCurrent()
        assertEquals(RecordingController.Phase.REVIEWING, controller.state.value.phase)
        assertNotNull(controller.state.value.voiceReview)
        controller.trimVoice(0.25f, 0.75f)
        controller.release()
        runCurrent()
        assertEquals(listOf("start VOICE", "pause VOICE", "resume VOICE", "stop VOICE", "trimVoice 500-1500", "discardVoice /v.ogg"), recorder.log)
        assertEquals(1_000L, (sent.single() as RecordedDraft.Voice).recording.durationMs)
        assertEquals(RecordingController.Phase.IDLE, controller.state.value.phase)
    }
}
