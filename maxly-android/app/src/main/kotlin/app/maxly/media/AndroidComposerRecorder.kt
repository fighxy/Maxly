package app.maxly.media

import android.Manifest
import app.maxly.calls.CallPermissions
import app.maxly.presentation.chat.ComposerRecorder
import app.maxly.presentation.chat.RecordedDraft
import app.maxly.presentation.chat.RecordingGesture
import app.maxly.presentation.chat.RecordingMode
import app.maxly.ui.chat.RecordingLive
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

    /** Кусок кружка с просмотра: копия дорожек без перекодирования рядом с исходником. */
    override suspend fun trim(recording: app.maxly.domain.VideoNoteRecording, fromMs: Long, toMs: Long): app.maxly.domain.VideoNoteRecording? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val source = java.io.File(recording.path)
            val target = java.io.File(source.parentFile, "note-cut-${System.currentTimeMillis()}.mp4")
            VideoNoteTrimmer.trim(source, fromMs, toMs, target)?.let { app.maxly.domain.VideoNoteRecording(target.absolutePath, it, recording.side) }
        }

    override fun setPaused(mode: RecordingMode, paused: Boolean): Boolean = when (mode) {
        RecordingMode.VOICE -> voice.setPaused(paused)
        RecordingMode.VIDEO -> note.setPaused(paused)
    }

    /**
     * Кусок голосового: пакеты Opus (или AAC до Android 10) копируются без перекодирования в
     * новый файл того же формата; волна — та же часть прежней.
     */
    override suspend fun trimVoice(recording: app.maxly.domain.VoiceRecording, fromMs: Long, toMs: Long): app.maxly.domain.VoiceRecording? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val source = java.io.File(recording.path)
            val ogg = source.extension.equals("ogg", ignoreCase = true)
            if (ogg && android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q) return@withContext null
            val format = if (ogg) android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_OGG else android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4
            val target = java.io.File(source.parentFile, "voice-cut-${System.currentTimeMillis()}.${source.extension}")
            val duration = VideoNoteTrimmer.trim(source, fromMs, toMs, target, format) ?: return@withContext null
            app.maxly.domain.VoiceRecording(target.absolutePath, duration, waveSlice(recording.waveform, fromMs, toMs, recording.durationMs), recording.fileName)
        }

    override suspend fun discardVoice(recording: app.maxly.domain.VoiceRecording) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { java.io.File(recording.path).delete() }
    }

    /** Часть волны [fromMs]..[toMs], растянутая обратно на прежнее число столбиков. */
    private fun waveSlice(wave: List<Int>, fromMs: Long, toMs: Long, durationMs: Long): List<Int> {
        if (wave.isEmpty() || durationMs <= 0) return wave
        val first = (wave.size * fromMs / durationMs).toInt().coerceIn(0, wave.size - 1)
        val last = (wave.size * toMs / durationMs).toInt().coerceIn(first + 1, wave.size)
        val part = wave.subList(first, last)
        return List(wave.size) { index -> part[index * part.size / wave.size] }
    }

    override suspend fun discard(recording: app.maxly.domain.VideoNoteRecording) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { java.io.File(recording.path).delete() }
    }
}
