package app.orbitle.media

import app.orbitle.presentation.chat.ComposerRecorder
import app.orbitle.presentation.chat.RecordedDraft
import app.orbitle.presentation.chat.RecordingGesture
import app.orbitle.presentation.chat.RecordingMode
import app.orbitle.ui.chat.RecordingLive
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

/**
 * Голосовое и кружок для поля ввода на ПК. Доступ к микрофону и камере спрашивает сама ОС
 * при первом включении, поэтому здесь он всегда «есть»; не дали — запись не включится.
 */
class DesktopComposerRecorder(
    private val voice: DesktopVoiceRecorder,
    val note: DesktopVideoNoteRecorder,
    scope: CoroutineScope,
) : ComposerRecorder {
    override var onLimit: (() -> Unit)? = null
        set(value) {
            field = value
            note.onLimit = value
        }

    val live: StateFlow<RecordingLive?> = combine(voice.live, note.elapsed) { voiceLive, noteMs ->
        when {
            voiceLive != null -> RecordingLive(voiceLive.elapsedMs, voiceLive.level)
            noteMs != null -> RecordingLive(noteMs, 0f)
            else -> null
        }
    }.stateIn(scope, SharingStarted.Eagerly, null)

    override fun access(mode: RecordingMode) = ComposerRecorder.Access.GRANTED

    override suspend fun requestAccess(mode: RecordingMode) = true

    override suspend fun start(mode: RecordingMode): Boolean = when (mode) {
        RecordingMode.VOICE -> voice.start()
        RecordingMode.VIDEO -> note.start()
    }

    override suspend fun stop(mode: RecordingMode): RecordedDraft? = when (mode) {
        RecordingMode.VOICE -> voice.finish(RecordingGesture.MINIMUM_DURATION_MS)?.let(RecordedDraft::Voice)
        RecordingMode.VIDEO -> note.stop()?.let(RecordedDraft::Note)
    }

    override suspend fun cancel(mode: RecordingMode) = when (mode) {
        RecordingMode.VOICE -> voice.cancel()
        RecordingMode.VIDEO -> note.cancel()
    }
}
