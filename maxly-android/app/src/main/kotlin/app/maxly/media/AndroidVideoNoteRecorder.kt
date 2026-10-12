package app.maxly.media

import android.annotation.SuppressLint
import android.content.Context
import android.util.Rational
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.MirrorMode
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.camera.video.ExperimentalPersistentRecording
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
 * Круг рисует уже пузырь, как на iOS. Камеру можно сменить посреди записи ([switchCamera]):
 * запись «постоянная» (`asPersistentRecording`) и переживает перепривязку к другой камере.
 */
@androidx.annotation.OptIn(markerClass = [ExperimentalPersistentRecording::class])
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

    private val _front = MutableStateFlow(true)

    /** Пишет фронтальная камера (по умолчанию) или основная. */
    val front: StateFlow<Boolean> = _front.asStateFlow()

    private val _flash = MutableStateFlow(false)

    /** Вспышка: у основной камеры — фонарик, у фронтальной экран светит белым (экран чата). */
    val flash: StateFlow<Boolean> = _flash.asStateFlow()

    private var provider: ProcessCameraProvider? = null
    private var group: UseCaseGroup? = null
    private var camera: androidx.camera.core.Camera? = null
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
            // Фронтальная — как в зеркале, как на iOS; основная — как есть.
            val video = VideoCapture.Builder(recorder).setMirrorMode(MirrorMode.MIRROR_MODE_ON_FRONT_ONLY).build()
            val group = UseCaseGroup.Builder()
                .setViewPort(ViewPort.Builder(Rational(1, 1), preview.display?.rotation ?: Surface.ROTATION_0).build())
                .addUseCase(previewCase)
                .addUseCase(video)
                .build()
            val front = cameras.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
            cameras.unbindAll()
            camera = cameras.bindToLifecycle(lifecycle, if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA, group)
            this.group = group
            _front.value = front
            val folder = File(context.cacheDir, "outgoing/notes").apply { mkdirs() }
            val target = File(folder, "note-${System.currentTimeMillis()}.mp4")
            val done = CompletableDeferred<Boolean>()
            finished = done
            file = target
            _elapsed.value = 0
            recording = video.output
                .prepareRecording(context, FileOutputOptions.Builder(target).build())
                .withAudioEnabled()
                .asPersistentRecording()
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

    /** Сменить камеру, не прерывая запись. Не вышло (одна камера) — остаётся прежняя. */
    fun switchCamera() {
        val cameras = provider ?: return
        val current = group ?: return
        if (recording == null) return
        val toFront = !_front.value
        val selector = if (toFront) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        if (!runCatching { cameras.hasCamera(selector) }.getOrDefault(false)) return
        try {
            cameras.unbindAll()
            camera = cameras.bindToLifecycle(lifecycle, selector, current)
            _front.value = toFront
        } catch (e: Exception) {
            // Другая камера не открылась: вернуть прежнюю, запись идёт дальше.
            camera = runCatching { cameras.bindToLifecycle(lifecycle, if (toFront) CameraSelector.DEFAULT_BACK_CAMERA else CameraSelector.DEFAULT_FRONT_CAMERA, current) }.getOrNull()
        }
        // Фонарик есть только у основной: у фронтальной светит экран.
        applyTorch()
    }

    /** Включить или выключить вспышку во время записи. */
    fun toggleFlash() {
        if (recording == null) return
        _flash.value = !_flash.value
        applyTorch()
    }

    private fun applyTorch() {
        val current = camera ?: return
        if (!current.cameraInfo.hasFlashUnit()) return
        runCatching { current.cameraControl.enableTorch(_flash.value && !_front.value) }
    }

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
        recording?.close()
        recording = null
        group = null
        camera = null
        _front.value = true
        _flash.value = false
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
