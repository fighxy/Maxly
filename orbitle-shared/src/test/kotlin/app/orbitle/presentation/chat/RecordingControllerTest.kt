package app.orbitle.presentation.chat

import app.orbitle.data.PreferenceStore
import app.orbitle.domain.VideoNoteRecording
import app.orbitle.domain.VoiceRecording
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
}

private class MemoryStore : PreferenceStore {
    val map = HashMap<String, String>()
    override fun get(key: String) = map[key]
    override fun put(key: String, value: String) {
        map[key] = value
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class RecordingControllerTest {
    private val recorder = FakeRecorder()
    private val store = MemoryStore()

    private fun TestScope.controller(): Pair<RecordingController, MutableList<RecordedDraft>> {
        val sent = mutableListOf<RecordedDraft>()
        val controller = RecordingController(recorder, backgroundScope, RecordingModeSettings(store))
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
    fun shortTapTogglesModeAndRemembersIt() = runTest {
        val (controller, _) = controller()
        controller.press()
        runCurrent()
        controller.release()
        runCurrent()
        assertEquals(RecordingMode.VIDEO, controller.state.value.mode)
        assertEquals(listOf("start VOICE", "cancel VOICE"), recorder.log)
        assertEquals("VIDEO", store.map["chat.recordMode"])
        assertNotNull(controller.state.value.hint)
        // Новое нажатие пишет кружок.
        controller.press()
        advanceTimeBy(200)
        controller.release()
        runCurrent()
        assertEquals(listOf("start VOICE", "cancel VOICE", "start VIDEO", "stop VIDEO"), recorder.log)
        assertEquals(RecordingMode.VIDEO, RecordingController(recorder, backgroundScope, RecordingModeSettings(store)).state.value.mode)
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
        // Отпускание после запроса доступа режим не меняет.
        assertEquals(RecordingMode.VOICE, controller.state.value.mode)
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
}
