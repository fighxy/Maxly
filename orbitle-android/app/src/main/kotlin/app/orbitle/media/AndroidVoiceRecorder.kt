package app.orbitle.media

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import app.orbitle.domain.VoiceRecording
import app.orbitle.presentation.chat.VoiceWave
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

/**
 * Запись голосового с микрофона. На Android 10+ — Ogg/Opus, как у iOS-версии; раньше система
 * Opus не пишет, тогда AAC в M4A. Пики уровня снимаются 10 раз в секунду: из них волна.
 */
class AndroidVoiceRecorder(private val context: Context, private val scope: CoroutineScope) {
    data class Live(val elapsedMs: Long = 0, val level: Float = 0f)

    private val _live = MutableStateFlow<Live?>(null)
    /** `null` — запись не идёт. */
    val live: StateFlow<Live?> = _live.asStateFlow()

    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    private val peaks = mutableListOf<Float>()
    private var ticker: Job? = null

    val isRecording: Boolean get() = recorder != null

    /** Начать запись. `false` — микрофон недоступен. */
    fun start(): Boolean {
        if (recorder != null) return true
        val opus = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val folder = File(context.cacheDir, "outgoing/voice").apply { mkdirs() }
        val target = File(folder, "voice-${System.currentTimeMillis()}.${if (opus) "ogg" else "m4a"}")
        val next = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        return try {
            next.setAudioSource(MediaRecorder.AudioSource.MIC)
            if (opus) {
                next.setOutputFormat(MediaRecorder.OutputFormat.OGG)
                next.setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
                next.setAudioSamplingRate(48_000)
            } else {
                next.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                next.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                next.setAudioSamplingRate(44_100)
            }
            next.setAudioChannels(1)
            next.setAudioEncodingBitRate(32_000)
            next.setOutputFile(target.absolutePath)
            next.prepare()
            next.start()
            recorder = next
            file = target
            startedAt = SystemClock.elapsedRealtime()
            peaks.clear()
            _live.value = Live()
            ticker = scope.launch {
                while (isActive) {
                    delay(100)
                    val current = recorder ?: break
                    val peak = VoiceWave.peak(runCatching { current.maxAmplitude }.getOrDefault(0))
                    peaks += peak
                    _live.value = Live(SystemClock.elapsedRealtime() - startedAt, VoiceWave.normalized(peak))
                }
            }
            true
        } catch (e: Exception) {
            next.release()
            target.delete()
            false
        }
    }

    /** Остановить и отдать запись; слишком короткая или сломанная — `null`, файл удаляется. */
    fun finish(minimumMs: Long): VoiceRecording? {
        val current = recorder ?: return null
        val target = file
        val duration = SystemClock.elapsedRealtime() - startedAt
        val ok = stop(current)
        if (!ok || target == null || duration < minimumMs || !target.exists() || target.length() == 0L) {
            target?.delete()
            return null
        }
        return VoiceRecording(target.absolutePath, duration, VoiceWave.wave(peaks.toList()), target.name.replaceBefore('.', "voice"))
    }

    /** Отменить: файл удаляется. */
    fun cancel() {
        val current = recorder ?: return
        stop(current)
        file?.delete()
    }

    private fun stop(current: MediaRecorder): Boolean {
        ticker?.cancel()
        ticker = null
        recorder = null
        _live.value = null
        val ok = runCatching { current.stop() }.isSuccess
        current.release()
        return ok
    }
}
