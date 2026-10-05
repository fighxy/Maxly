package app.orbitle.media

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asComposeImageBitmap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.ImageInfo
import java.io.BufferedInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.Locale
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.SourceDataLine
import kotlin.coroutines.coroutineContext

/**
 * Встроенный проигрыватель видео на компьютере. Тот же `ffmpeg`, что у голосовых, декодирует
 * кадры в RGBA (поток PAM в канал) и звук в PCM для Java Sound. Кадры идут с постоянной
 * частотой (фильтр `fps`), поэтому время кадра — его номер; часы — время с запуска без пауз,
 * опоздавшие кадры пропускаются. Перемотка перезапускает декодеры с нужной секунды.
 *
 * Удалённый ролик сначала скачивается в кэш (`DesktopVideo.materialize`): так перемотка и звук
 * не качают его заново. Без ffmpeg в PATH состояние — [State.failed], экран предлагает
 * системный проигрыватель.
 */
class DesktopVideoPlayer(private val scope: CoroutineScope) {

    data class State(
        val frame: ImageBitmap? = null,
        val positionMs: Long = 0,
        /** `0` — длительность ещё не известна. */
        val durationMs: Long = 0,
        val isPlaying: Boolean = false,
        /** Ролик качается или первый кадр ещё не готов. */
        val isBuffering: Boolean = false,
        val ended: Boolean = false,
        /** Не открылся: нет ffmpeg, файл не скачался или не декодируется. */
        val failed: Boolean = false,
    ) {
        val progress: Float get() = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    @Volatile private var file: File? = null
    @Volatile private var session: Session? = null
    @Volatile private var wantPlaying = false
    @Volatile private var muted = false
    @Volatile private var loop = false
    /** Растёт при каждом открытии и сбросе: запоздавший запуск прежнего ролика не стартует. */
    @Volatile private var generation = 0
    private var opening: Job? = null

    /**
     * Открывает ролик: адрес CDN (качается с [userAgent]) или путь к файлу. [muted] — без звука
     * (предпросмотр), [loop] — по кругу.
     */
    fun open(source: String, userAgent: String, autoplay: Boolean = true, muted: Boolean = false, loop: Boolean = false) {
        release()
        val ticket = generation
        this.muted = muted
        this.loop = loop
        wantPlaying = autoplay
        _state.value = State(isBuffering = true, isPlaying = autoplay)
        opening = scope.launch(Dispatchers.IO) {
            val local = try {
                DesktopVideo.materialize(source, userAgent)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (ticket == generation) fail()
                return@launch
            }
            if (ticket != generation) return@launch
            file = local
            start(local, 0, ticket)
        }
    }

    fun play() {
        wantPlaying = true
        if (_state.value.ended) {
            seek(0f)
            return
        }
        session?.resume()
        _state.update { it.copy(isPlaying = true) }
    }

    fun pause() {
        wantPlaying = false
        session?.pause()
        _state.update { it.copy(isPlaying = false) }
    }

    fun toggle() = if (_state.value.isPlaying) pause() else play()

    /** Перемотка на долю ролика; играет дальше, если играл. */
    fun seek(fraction: Float) {
        val local = file ?: return
        val duration = _state.value.durationMs
        val at = if (duration > 0) (duration * fraction.coerceIn(0f, 1f)).toLong() else 0L
        val ticket = generation
        _state.update { it.copy(positionMs = at, ended = false, isBuffering = true, isPlaying = wantPlaying) }
        scope.launch(Dispatchers.IO) { start(local, at, ticket) }
    }

    /** Останавливает декодеры и звук, забывает ролик. */
    fun release() {
        generation++
        opening?.cancel()
        opening = null
        session?.stop()
        session = null
        file = null
        _state.value = State()
    }

    @Synchronized
    private fun start(local: File, at: Long, ticket: Int) {
        if (ticket != generation) return
        session?.stop()
        val next = Session(local, at)
        session = next
        val video = try {
            ProcessBuilder(VideoCommands.video(local.absolutePath, at)).start()
        } catch (e: IOException) {
            fail()
            return
        }
        next.video = video
        next.jobs += scope.launch(Dispatchers.IO) { readLog(next, video) }
        next.jobs += scope.launch(Dispatchers.IO) { runVideo(next, video) }
        if (!muted) next.jobs += scope.launch(Dispatchers.IO) { runAudio(next) }
    }

    private fun fail() {
        wantPlaying = false
        _state.update { it.copy(failed = true, isBuffering = false, isPlaying = false) }
    }

    private suspend fun runVideo(s: Session, process: Process) {
        val reader = PamReader(BufferedInputStream(process.inputStream, 1 shl 20))
        var index = 0L
        var shown = 0
        try {
            while (!s.stopped) {
                coroutineContext.ensureActive()
                val frame = reader.next() ?: break
                val at = s.startMs + index * 1000 / VideoCommands.FPS
                index++
                if (shown > 0) {
                    while (true) {
                        coroutineContext.ensureActive()
                        val wait = at - s.clock.nowMs()
                        if (wait <= 0) break
                        delay(wait.coerceAtMost(20))
                    }
                    // Опоздавший кадр не показываем: картинка догоняет звук.
                    if (s.clock.nowMs() - at > LATE_MS) continue
                }
                show(s, frame, at)
                if (shown++ == 0) s.begin()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            if (s.stopped) return
        }
        if (s.stopped || session !== s) return
        when {
            shown == 0 -> fail()
            loop -> start(s.file, 0, generation)
            else -> {
                wantPlaying = false
                _state.update { it.copy(isPlaying = false, ended = true, positionMs = maxOf(it.durationMs, it.positionMs)) }
            }
        }
    }

    private fun show(s: Session, frame: PamFrame, at: Long) {
        if (session !== s) return
        val info = ImageInfo(frame.width, frame.height, ColorType.RGBA_8888, ColorAlphaType.UNPREMUL)
        val bitmap = Bitmap()
        bitmap.installPixels(info, frame.rgba, frame.width * 4)
        bitmap.setImmutable()
        val image = bitmap.asComposeImageBitmap()
        _state.update { it.copy(frame = image, positionMs = at, isBuffering = false, failed = false) }
    }

    /** Длительность — из журнала ffmpeg (`Duration: 00:00:15.04`); журнал заодно вычитывается до конца. */
    private fun readLog(s: Session, process: Process) {
        runCatching {
            process.errorStream.bufferedReader().useLines { lines ->
                lines.forEach { line ->
                    val duration = VideoCommands.durationMs(line) ?: return@forEach
                    if (session === s && _state.value.durationMs <= 0) _state.update { it.copy(durationMs = duration) }
                }
            }
        }
    }

    /** Звук: PCM 44,1 кГц стерео в Java Sound. Пока линия не запущена, буфер наполняется заранее. */
    private fun runAudio(s: Session) {
        val process = try {
            ProcessBuilder(VideoCommands.audio(s.file.absolutePath, s.startMs))
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start()
        } catch (e: IOException) {
            return
        }
        s.audio = process
        val format = AudioFormat(SAMPLE_RATE.toFloat(), 16, 2, true, false)
        val speaker = try {
            AudioSystem.getSourceDataLine(format).apply { open(format, SAMPLE_RATE * 4 / 5) }
        } catch (e: Exception) {
            process.destroyForcibly()
            return
        }
        s.line = speaker
        if (s.stopped) {
            runCatching { speaker.close() }
            process.destroyForcibly()
            return
        }
        if (s.clock.isRunning) speaker.start()
        val buffer = ByteArray(8192)
        try {
            val input = process.inputStream
            while (!s.stopped) {
                val read = input.read(buffer)
                if (read < 0) break
                speaker.write(buffer, 0, read)
            }
            if (!s.stopped) speaker.drain()
        } catch (_: Exception) {
            // Остановили или нет звуковой дорожки: картинка идёт по своим часам.
        } finally {
            runCatching { speaker.close() }
            process.destroyForcibly()
        }
    }

    /** Один запуск декодеров с секунды [startMs]. Часы стоят до первого кадра. */
    private inner class Session(val file: File, val startMs: Long) {
        val clock = PlaybackClock(startMs)
        val jobs = mutableListOf<Job>()
        @Volatile var video: Process? = null
        @Volatile var audio: Process? = null
        @Volatile var line: SourceDataLine? = null
        @Volatile var begun = false
        @Volatile var stopped = false

        /** Первый кадр на экране: пошли часы и звук, если ролик должен играть. */
        fun begin() {
            begun = true
            if (wantPlaying) resume()
        }

        fun resume() {
            if (!begun || stopped) return
            clock.resume()
            runCatching { line?.start() }
        }

        fun pause() {
            clock.pause()
            runCatching { line?.stop() }
        }

        fun stop() {
            stopped = true
            jobs.forEach { it.cancel() }
            runCatching { video?.destroyForcibly() }
            runCatching { audio?.destroyForcibly() }
            runCatching {
                line?.stop()
                line?.flush()
                line?.close()
            }
        }
    }

    private companion object {
        const val SAMPLE_RATE = 44_100
        /** Кадр, опоздавший больше чем на столько, пропускается. */
        const val LATE_MS = 120L
    }
}

/** Часы воспроизведения: время ролика с паузами. Стоят, пока не запущены. */
internal class PlaybackClock(private var baseMs: Long, private val nanos: () -> Long = System::nanoTime) {
    private var runningSince: Long? = null

    val isRunning: Boolean @Synchronized get() = runningSince != null

    @Synchronized
    fun nowMs(): Long = runningSince?.let { baseMs + (nanos() - it) / 1_000_000 } ?: baseMs

    @Synchronized
    fun resume() {
        if (runningSince == null) runningSince = nanos()
    }

    @Synchronized
    fun pause() {
        runningSince?.let { baseMs += (nanos() - it) / 1_000_000 }
        runningSince = null
    }
}

/** Команды ffmpeg проигрывателя. */
internal object VideoCommands {
    /** Кадров в секунду на выходе: время кадра — его номер. */
    const val FPS = 30
    /** Больше этого по длинной стороне кадр не декодируется: экрану хватает, канал не забит. */
    const val MAX_SIDE = 960

    fun video(path: String, startMs: Long): List<String> = listOf(
        "ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-loglevel", "info",
        "-ss", seconds(startMs), "-i", path,
        "-an", "-sn",
        "-vf", "fps=$FPS,scale=w='min($MAX_SIDE,iw)':h='min($MAX_SIDE,ih)':force_original_aspect_ratio=decrease",
        "-f", "image2pipe", "-c:v", "pam", "-pix_fmt", "rgba", "-",
    )

    fun audio(path: String, startMs: Long): List<String> = listOf(
        "ffmpeg", "-nostdin", "-hide_banner", "-nostats", "-loglevel", "error",
        "-ss", seconds(startMs), "-i", path,
        "-vn", "-sn", "-f", "s16le", "-ac", "2", "-ar", "44100", "-",
    )

    fun seconds(ms: Long): String = String.format(Locale.ROOT, "%.3f", ms.coerceAtLeast(0) / 1000.0)

    private val DURATION = Regex("""Duration:\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)""")

    /** `Duration: 00:01:02.50` из журнала → миллисекунды; `N/A` и прочее — `null`. */
    fun durationMs(line: String): Long? {
        val match = DURATION.find(line) ?: return null
        val (h, m, s) = match.destructured
        val total = h.toLong() * 3_600_000 + m.toLong() * 60_000 + (s.toDouble() * 1000).toLong()
        return total.takeIf { it > 0 }
    }
}

/** Кадр PAM: ширина, высота и пиксели RGBA построчно. */
internal class PamFrame(val width: Int, val height: Int, val rgba: ByteArray)

/**
 * Читает поток кадров PAM (`P7`, `WIDTH`, `HEIGHT`, `DEPTH 4`, `ENDHDR`, затем пиксели) из
 * `image2pipe`. Заголовок у каждого кадра свой, поэтому размер знать заранее не нужно.
 */
internal class PamReader(private val input: InputStream) {
    /** Следующий кадр или `null` в конце потока (в том числе посреди кадра). */
    fun next(): PamFrame? {
        val magic = line() ?: return null
        if (magic != "P7") throw IOException("не кадр PAM: $magic")
        var width = 0
        var height = 0
        var depth = 0
        while (true) {
            val header = line() ?: return null
            if (header == "ENDHDR") break
            val key = header.substringBefore(' ')
            val value = header.substringAfter(' ', "").trim()
            when (key) {
                "WIDTH" -> width = value.toIntOrNull() ?: 0
                "HEIGHT" -> height = value.toIntOrNull() ?: 0
                "DEPTH" -> depth = value.toIntOrNull() ?: 0
            }
        }
        if (width <= 0 || height <= 0 || depth != 4) throw IOException("кадр PAM ${width}x$height, глубина $depth")
        val pixels = ByteArray(width * height * 4)
        var offset = 0
        while (offset < pixels.size) {
            val read = input.read(pixels, offset, pixels.size - offset)
            if (read < 0) return null
            offset += read
        }
        return PamFrame(width, height, pixels)
    }

    private fun line(): String? {
        val text = StringBuilder()
        while (true) {
            val byte = input.read()
            if (byte < 0) return if (text.isEmpty()) null else text.toString()
            if (byte == '\n'.code) return text.toString()
            text.append(byte.toChar())
        }
    }
}
