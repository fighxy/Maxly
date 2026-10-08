package app.orbitle.media

import android.Manifest
import app.orbitle.calls.CallPermissions
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

/** Голосовое и кружок для поля ввода на Android: микрофон — MediaRecorder, кружок — CameraX. */
class AndroidComposerRecorder(
    private val voice: AndroidVoiceRecorder,
    val note: AndroidVideoNoteRecorder,
    scope: CoroutineScope,
) : ComposerRecorder {
    override var onLimit: (() -> Unit)? = null
        set(value) {
            field = value
            note.onLimit = value
        }

    /** Время и громкость идущей записи — голосового или кружка. */
    val live: StateFlow<RecordingLive?> = combine(voice.live, note.elapsed) { voiceLive, noteMs ->
        when {
            voiceLive != null -> RecordingLive(voiceLive.elapsedMs, voiceLive.level)
            noteMs != null -> RecordingLive(noteMs, 0f)
            else -> null
        }
    }.stateIn(scope, SharingStarted.Eagerly, null)

    private fun permissions(mode: RecordingMode) =
        if (mode == RecordingMode.VOICE) listOf(Manifest.permission.RECORD_AUDIO)
        else listOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)

    override fun access(mode: RecordingMode): ComposerRecorder.Access =
        if (permissions(mode).all(CallPermissions::granted)) ComposerRecorder.Access.GRANTED else ComposerRecorder.Access.ASK

    override suspend fun requestAccess(mode: RecordingMode): Boolean = permissions(mode).all { CallPermissions.ensure(it) }

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
