package app.maxly.media

import android.annotation.SuppressLint
import android.content.Context
import android.util.Rational
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import app.maxly.domain.VideoNoteRecording
import app.maxly.presentation.chat.RecordingController
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

/**
 * Запись кружка: фронтальная камера (CameraX), кадр обрезается по центру в квадрат, до минуты.
 * Круг рисует уже пузырь, как на iOS.
 */
class AndroidVideoNoteRecorder(private val context: Context, private val lifecycle: LifecycleOwner) {
    private val _elapsed = MutableStateFlow<Long?>(null)

    /** Время идущей записи, мс; `null` — запись не идёт. */
    val elapsed: StateFlow<Long?> = _elapsed.asStateFlow()

    /** Превью камеры под пальцем: экран чата показывает его кругом. */
    val preview: PreviewView by lazy {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            // TextureView: превью обрезается кругом, SurfaceView бы торчал квадратом.
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }

    /** Запись упёрлась в минуту. */
    var onLimit: (() -> Unit)? = null

    private var provider: ProcessCameraProvider? = null
    private var recording: Recording? = null
    private var file: File? = null
    private var finished: CompletableDeferred<Boolean>? = null

    @SuppressLint("MissingPermission")
    suspend fun start(): Boolean {
        if (recording != null) return true
        return try {
            val cameras = ProcessCameraProvider.awaitInstance(context)
            provider = cameras
            val previewCase = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
            val recorder = Recorder.Builder()
                .setQualitySelector(QualitySelector.from(Quality.SD, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)))
                .build()
            val video = VideoCapture.withOutput(recorder)
            val group = UseCaseGroup.Builder()
                .setViewPort(ViewPort.Builder(Rational(1, 1), preview.display?.rotation ?: Surface.ROTATION_0).build())
                .addUseCase(previewCase)
                .addUseCase(video)
                .build()
            val selector = if (cameras.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
            cameras.unbindAll()
            cameras.bindToLifecycle(lifecycle, selector, group)
            val folder = File(context.cacheDir, "outgoing/notes").apply { mkdirs() }
            val target = File(folder, "note-${System.currentTimeMillis()}.mp4")
            val done = CompletableDeferred<Boolean>()
            finished = done
            file = target
            _elapsed.value = 0
            recording = video.output
                .prepareRecording(context, FileOutputOptions.Builder(target).build())
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(context)) { event ->
                    when (event) {
                        is VideoRecordEvent.Status -> {
                            val ms = event.recordingStats.recordedDurationNanos / 1_000_000
                            if (_elapsed.value != null) _elapsed.value = ms
                            if (ms >= RecordingController.VIDEO_NOTE_LIMIT_MS) onLimit?.invoke()
                        }
                        is VideoRecordEvent.Finalize -> {
                            val ms = event.recordingStats.recordedDurationNanos / 1_000_000
                            if (ms > 0) lastDurationMs = ms
                            done.complete(target.length() > 0)
                        }
                        else -> Unit
                    }
                }
            true
        } catch (e: Exception) {
            release()
            false
        }
    }

    private var lastDurationMs = 0L

    /** Остановить и отдать ролик; `null` — короче секунды или не записался. */
    suspend fun stop(): VideoNoteRecording? {
        val current = recording ?: return null
        val target = file
        val elapsedMs = _elapsed.value ?: 0
        current.stop()
        val ok = withTimeoutOrNull(5_000) { finished?.await() } == true
        release()
        val durationMs = maxOf(lastDurationMs, elapsedMs)
        if (!ok || target == null || durationMs < 1_000) {
            target?.delete()
            return null
        }
        return VideoNoteRecording(target.absolutePath, durationMs, SIDE)
    }

    suspend fun cancel() {
        val current = recording ?: return
        val target = file
        current.stop()
        withTimeoutOrNull(3_000) { finished?.await() }
        release()
        target?.delete()
    }

    private fun release() {
        recording = null
        finished = null
        file = null
        lastDurationMs = 0
        _elapsed.value = null
        runCatching { provider?.unbindAll() }
    }

    private companion object {
        const val SIDE = 480
    }
}
