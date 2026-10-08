package app.orbitle.media

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import app.orbitle.calls.DesktopWebRtc
import app.orbitle.domain.VideoNoteRecording
import app.orbitle.platform.AppPaths
import app.orbitle.presentation.chat.RecordingController
import dev.onvoid.webrtc.media.FourCC
import dev.onvoid.webrtc.media.MediaDevices
import dev.onvoid.webrtc.media.video.VideoBufferConverter
import dev.onvoid.webrtc.media.video.VideoCaptureCapability
import dev.onvoid.webrtc.media.video.VideoDeviceSource
import dev.onvoid.webrtc.media.video.VideoFrame
import dev.onvoid.webrtc.media.video.VideoTrack
import dev.onvoid.webrtc.media.video.VideoTrackSink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageInfo
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.DataLine
import javax.sound.sampled.TargetDataLine
import kotlin.math.abs

/**
 * Кружок на ПК: камера через webrtc-java, звук через Java Sound, ffmpeg кодирует квадрат
 * 480×480 H.264 и AAC в MP4 — тот же формат, что у телефона. До минуты.
 */
class DesktopVideoNoteRecorder(private val scope: CoroutineScope) {
    private val _elapsed = MutableStateFlow<Long?>(null)

    /** Время идущей записи, мс; `null` — запись не идёт. */
    val elapsed: StateFlow<Long?> = _elapsed.asStateFlow()

    private val _preview = MutableStateFlow<ImageBitmap?>(null)

    /** Последний кадр камеры (квадрат) для превью кругом. */
    val preview: StateFlow<ImageBitmap?> = _preview.asStateFlow()

    var onLimit: (() -> Unit)? = null

    private var source: VideoDeviceSource? = null
    private var track: VideoTrack? = null
    private var sink: VideoTrackSink? = null
    private var encoder: Process? = null
    private var video: File? = null
    private var audio: File? = null
    private var mic: TargetDataLine? = null
    private var jobs = mutableListOf<Job>()
    private var startedAt = 0L

    @Volatile
    private var latest: ByteArray? = null

    suspend fun start(): Boolean = withContext(Dispatchers.IO) {
        if (encoder != null) return@withContext true
        val folder = File(AppPaths.cacheDir, "outgoing/notes").apply { mkdirs() }
        val stamp = System.currentTimeMillis()
        val videoFile = File(folder, "note-$stamp-video.mp4")
        val audioFile = File(folder, "note-$stamp.pcm")
        try {
            val device = MediaDevices.getVideoCaptureDevices().firstOrNull() ?: return@withContext false
            val camera = VideoDeviceSource()
            camera.setVideoCaptureDevice(device)
            capability(MediaDevices.getVideoCaptureCapabilities(device))?.let(camera::setVideoCaptureCapability)
            camera.start()
            val videoTrack = DesktopWebRtc.factory.createVideoTrack("note-$stamp", camera)
            val frames = NoteSink { yuv, image ->
                latest = yuv
                if (image != null) _preview.value = image
            }
            videoTrack.addSink(frames)
            val process = ProcessBuilder(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-f", "rawvideo", "-pix_fmt", "yuv420p", "-s", "${SIDE}x$SIDE", "-r", "$FPS", "-i", "pipe:0",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "26", "-pix_fmt", "yuv420p", videoFile.absolutePath,
            ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
            val format = AudioFormat(48_000f, 16, 1, true, false)
            val line = AudioSystem.getLine(DataLine.Info(TargetDataLine::class.java, format)) as TargetDataLine
            line.open(format)
            line.start()
            source = camera
            track = videoTrack
            sink = frames
            encoder = process
            video = videoFile
            audio = audioFile
            mic = line
            latest = null
            startedAt = System.currentTimeMillis()
            _elapsed.value = 0
            jobs += scope.launch(Dispatchers.IO) { writeFrames(process.outputStream) }
            jobs += scope.launch(Dispatchers.IO) { writeAudio(line, audioFile) }
            jobs += scope.launch {
                while (isActive && encoder != null) {
                    delay(100)
                    val ms = System.currentTimeMillis() - startedAt
                    _elapsed.value = ms
                    if (ms >= RecordingController.VIDEO_NOTE_LIMIT_MS) onLimit?.invoke()
                }
            }
            true
        } catch (_: Exception) {
            release()
            videoFile.delete()
            audioFile.delete()
            false
        }
    }

    /** Ровно [FPS] кадров в секунду: последний кадр камеры, до первого — чёрный. */
    private suspend fun writeFrames(out: OutputStream) {
        val black = ByteArray(SIDE * SIDE * 3 / 2).also { bytes ->
            bytes.fill(16, 0, SIDE * SIDE)
            bytes.fill(-128, SIDE * SIDE, bytes.size)
        }
        var next = System.nanoTime()
        try {
            while (encoder != null) {
                out.write(latest ?: black)
                next += 1_000_000_000L / FPS
                val wait = (next - System.nanoTime()) / 1_000_000
                if (wait > 0) delay(wait)
            }
        } catch (_: Exception) {
        }
    }

    private fun writeAudio(line: TargetDataLine, file: File) {
        val buffer = ByteArray(4_800)
        runCatching {
            FileOutputStream(file).use { out ->
                while (mic === line) {
                    val read = line.read(buffer, 0, buffer.size)
                    if (read <= 0) break
                    out.write(buffer, 0, read)
                }
            }
        }
    }

    /** Остановить и собрать MP4; `null` — короче секунды или ffmpeg не справился. */
    suspend fun stop(): VideoNoteRecording? = withContext(Dispatchers.IO) {
        val process = encoder ?: return@withContext null
        val videoFile = video
        val audioFile = audio
        val durationMs = System.currentTimeMillis() - startedAt
        release()
        runCatching { process.outputStream.close() }
        runCatching { process.waitFor() }
        if (videoFile == null || audioFile == null || durationMs < 1_000 || !videoFile.exists()) {
            videoFile?.delete()
            audioFile?.delete()
            return@withContext null
        }
        val note = File(videoFile.parentFile, videoFile.name.replace("-video.mp4", ".mp4"))
        val muxed = runCatching {
            ProcessBuilder(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", videoFile.absolutePath,
                "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", audioFile.absolutePath,
                "-c:v", "copy", "-c:a", "aac", "-b:a", "64k", "-shortest", "-movflags", "+faststart", note.absolutePath,
            ).redirectError(ProcessBuilder.Redirect.DISCARD).start().waitFor() == 0 && note.length() > 0
        }.getOrDefault(false)
        videoFile.delete()
        audioFile.delete()
        if (!muxed) {
            note.delete()
            return@withContext null
        }
        VideoNoteRecording(note.absolutePath, durationMs, SIDE)
    }

    suspend fun cancel() = withContext(Dispatchers.IO) {
        val process = encoder ?: return@withContext
        val files = listOfNotNull(video, audio)
        release()
        runCatching { process.destroy() }
        files.forEach { it.delete() }
    }

    private fun release() {
        jobs.forEach { it.cancel() }
        jobs.clear()
        val line = mic
        mic = null
        runCatching { line?.stop(); line?.close() }
        val frames = sink
        sink = null
        runCatching { frames?.let { track?.removeSink(it) } }
        runCatching { source?.stop() }
        runCatching { track?.dispose() }
        runCatching { source?.dispose() }
        track = null
        source = null
        encoder = null
        video = null
        audio = null
        latest = null
        _elapsed.value = null
        _preview.value = null
    }

    /** Ближе всего к 640×480 и не больше 30 кадров в секунду. */
    private fun capability(list: List<VideoCaptureCapability>): VideoCaptureCapability? {
        val target = 640 * 480
        return list.filter { it.frameRate in 1..30 }.ifEmpty { list }
            .minWithOrNull(compareBy<VideoCaptureCapability> { abs(it.width * it.height - target) }.thenByDescending { it.frameRate })
            ?.let { VideoCaptureCapability(it.width, it.height, it.frameRate.coerceAtMost(30)) }
    }

    internal companion object {
        const val SIDE = 480
        const val FPS = 25
    }
}

/** Кадр камеры → квадрат 480×480 по центру: YUV для ffmpeg и картинка для превью (до 15 в секунду). */
private class NoteSink(private val onFrame: (ByteArray, ImageBitmap?) -> Unit) : VideoTrackSink {
    private var lastPreview = 0L
    private val argb = ByteArray(DesktopVideoNoteRecorder.SIDE * DesktopVideoNoteRecorder.SIDE * 4)

    override fun onVideoFrame(frame: VideoFrame) {
        val side = DesktopVideoNoteRecorder.SIDE
        val buffer = frame.buffer
        val crop = minOf(buffer.width, buffer.height)
        if (crop <= 0) return
        val square = runCatching {
            buffer.cropAndScale((buffer.width - crop) / 2, (buffer.height - crop) / 2, crop, crop, side, side)
        }.getOrNull() ?: return
        try {
            val i420 = square.toI420()
            try {
                val yuv = ByteArray(side * side * 3 / 2)
                copyPlane(i420.dataY, i420.strideY, side, side, yuv, 0)
                copyPlane(i420.dataU, i420.strideU, side / 2, side / 2, yuv, side * side)
                copyPlane(i420.dataV, i420.strideV, side / 2, side / 2, yuv, side * side + side * side / 4)
                val now = System.nanoTime()
                var image: ImageBitmap? = null
                if (now - lastPreview > 66_000_000L) {
                    lastPreview = now
                    runCatching {
                        VideoBufferConverter.convertFromI420(i420, argb, FourCC.ARGB)
                        image = Image.makeRaster(ImageInfo(side, side, ColorType.BGRA_8888, ColorAlphaType.OPAQUE), argb.copyOf(), side * 4)
                            .toComposeImageBitmap()
                    }
                }
                onFrame(yuv, image)
            } finally {
                i420.release()
            }
        } finally {
            square.release()
        }
    }

    private fun copyPlane(plane: java.nio.ByteBuffer, stride: Int, width: Int, height: Int, out: ByteArray, offset: Int) {
        val source = plane.duplicate()
        for (row in 0 until height) {
            source.position(row * stride)
            source.get(out, offset + row * width, width)
        }
    }
}
