package app.maxly.media

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
import kotlinx.coroutines.cancelChildren
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
 * Удалённый ролик играет, пока качается: загрузка идёт в кэш одним соединением, а ffmpeg читает
 * её через [LocalVideoServer] (дальнее место при перемотке — прямо у CDN). Догнав загрузку (кадр
 * не пришёл вовремя), проигрыватель встаёт на буферизацию до запаса в пару секунд ролика.
 * Скачанный ролик дальше играет из файла. Без ffmpeg в PATH состояние — [State.failed], экран
 * предлагает системный проигрыватель.
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
        /**
         * Ролик качается в кэш до начала просмотра (сервер не сказал размер): доля 0…1; `null` —
         * не ждём загрузку.
         */
        val downloading: Float? = null,
        /** Сколько ролика уже на диске, 0…1: полоса подгрузки на перемотке. */
        val buffered: Float = 0f,
        /** Громкость 0…1 и выключен ли звук. */
        val volume: Float = 1f,
        val muted: Boolean = false,
    ) {
        val progress: Float get() = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Что читает ffmpeg: путь к файлу или адрес [LocalVideoServer]. */
    @Volatile private var input: String? = null
    @Volatile private var streaming: StreamingDownload? = null
    @Volatile private var served: String? = null
    @Volatile private var session: Session? = null
    @Volatile private var wantPlaying = false
    @Volatile private var muted = false
    @Volatile private var loop = false
    /** Громкость и выключенный звук для [State]; линия звука читает их на каждом куске. */
    @Volatile private var volume = 1f
    @Volatile private var silenced = false
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
        _state.value = fresh().copy(isBuffering = true, isPlaying = autoplay)
        opening = scope.launch(Dispatchers.IO) {
            DesktopVideo.local(source, userAgent)?.let { local ->
                if (ticket != generation) return@launch
                input = local.absolutePath
                _state.update { it.copy(buffered = 1f) }
                start(local.absolutePath, 0, ticket)
                return@launch
            }
            val download = DesktopVideo.stream(source, userAgent)
            streaming = download
            launch { download.run() }
            launch { download.progress.collect { fraction -> if (ticket == generation) _state.update { it.copy(buffered = fraction) } } }
            download.awaitReady()
            if (ticket != generation) return@launch
            when {
                download.failure != null -> fail()
                download.finished -> Unit
                download.total >= 0 -> {
                    val url = LocalVideoServer.register(download)
                    served = url
                    input = url
                    start(url, 0, ticket)
                }
                // Размер неизвестен — без диапазонов перемотка не работает: ждём загрузку.
                else -> launch { download.progress.collect { fraction -> if (ticket == generation) _state.update { it.copy(downloading = fraction) } } }
            }
            val finished = download.awaitFinished()
            if (ticket != generation) return@launch
            if (!finished) {
                if (session == null) fail()
                coroutineContext.cancelChildren()
                return@launch
            }
            // Дальше перемотка и повтор — из файла в кэше.
            val local = download.target.absolutePath
            val waiting = input == null
            input = local
            _state.update { it.copy(downloading = null, buffered = 1f) }
            if (waiting) start(local, 0, ticket)
            coroutineContext.cancelChildren()
        }
    }

    /**
     * Сторож запуска, который читает ролик на ходу: часы ушли дальше последнего кадра на
     * [STALL_MS], а ролик ещё качается — значит, упёрлись в загрузку. Часы возвращаются к кадру и
     * стоят, звук молчит, на экране буферизация — пока не скачается запас в [REFILL_MS] ролика.
     */
    private suspend fun watchDownload(s: Session, download: StreamingDownload) {
        var refillTo = 0L
        while (!s.stopped && session === s) {
            delay(100)
            if (download.finished || download.failure != null) {
                if (s.stalled) unstall(s)
                return
            }
            if (s.stalled) {
                if (download.done >= refillTo) unstall(s)
            } else if (s.begun && s.clock.isRunning && s.clock.nowMs() - s.lastShownMs > STALL_MS) {
                s.stalled = true
                s.pause()
                s.clock.rewind(s.lastShownMs)
                val duration = _state.value.durationMs
                val bytesPerMs = if (duration > 0 && download.total > 0) download.total.toDouble() / duration else 0.0
                refillTo = download.done + maxOf(MIN_REFILL, (bytesPerMs * REFILL_MS).toLong())
                _state.update { it.copy(isBuffering = true) }
            }
        }
    }

    private fun unstall(s: Session) {
        s.stalled = false
        if (wantPlaying) s.resume()
        if (session === s) _state.update { it.copy(isBuffering = false) }
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
        val local = input ?: return
        val duration = _state.value.durationMs
        val at = if (duration > 0) (duration * fraction.coerceIn(0f, 1f)).toLong() else 0L
        val ticket = generation
        _state.update { it.copy(positionMs = at, ended = false, isBuffering = true, isPlaying = wantPlaying) }
        scope.launch(Dispatchers.IO) { start(local, at, ticket) }
    }

    /** Перемотка на [ms] от начала. */
    fun seekTo(ms: Long) {
        val duration = _state.value.durationMs
        if (duration > 0) seek(ms.toFloat() / duration)
    }

    /** Громкость 0…1; ненулевая заодно включает звук. */
    fun setVolume(value: Float) {
        volume = value.coerceIn(0f, 1f)
        if (volume > 0f) silenced = false
        _state.update { it.copy(volume = volume, muted = silenced) }
    }

    fun setMuted(value: Boolean) {
        silenced = value
        _state.update { it.copy(muted = value) }
    }

    private fun fresh() = State(volume = volume, muted = silenced)

    /** Останавливает декодеры и звук, забывает ролик. */
    fun release() {
        generation++
        opening?.cancel()
        opening = null
        session?.stop()
        session = null
        streaming?.cancel()
        streaming = null
        served?.let(LocalVideoServer::unregister)
        served = null
        input = null
        _state.value = fresh()
    }

    @Synchronized
    private fun start(local: String, at: Long, ticket: Int) {
        if (ticket != generation) return
        session?.stop()
        val next = Session(local, at)
        session = next
        val video = try {
            VideoCommands.process(VideoCommands.video(local, at)).start()
        } catch (e: IOException) {
            fail()
            return
        }
        next.video = video
        next.jobs += scope.launch(Dispatchers.IO) { readLog(next, video) }
        next.jobs += scope.launch(Dispatchers.IO) { runVideo(next, video) }
        if (!muted) next.jobs += scope.launch(Dispatchers.IO) { runAudio(next) }
        val download = streaming
        if (download != null && local == served) next.jobs += scope.launch { watchDownload(next, download) }
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
            loop -> start(input ?: s.input, 0, generation)
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
        s.lastShownMs = at
        // Кадр, показанный уже после упора в загрузку, буферизацию не снимает.
        _state.update { it.copy(frame = image, positionMs = at, isBuffering = s.stalled, failed = false) }
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
            VideoCommands.process(VideoCommands.audio(s.input, s.startMs))
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
                val gain = if (silenced) 0f else volume * volume
                if (gain < 0.999f) scalePcm16(buffer, read, gain)
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
    private inner class Session(val input: String, val startMs: Long) {
        val clock = PlaybackClock(startMs)
        val jobs = mutableListOf<Job>()
        @Volatile var video: Process? = null
        @Volatile var audio: Process? = null
        @Volatile var line: SourceDataLine? = null
        @Volatile var begun = false
        @Volatile var stopped = false
        /** Ждём загрузку: часы стоят, пока не придёт запас. */
        @Volatile var stalled = false
        /** Время последнего показанного кадра. */
        @Volatile var lastShownMs = startMs

        /** Первый кадр на экране: пошли часы и звук, если ролик должен играть. */
        fun begin() {
            begun = true
            if (wantPlaying) resume()
        }

        fun resume() {
            if (!begun || stopped || stalled) return
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
        /** Нового кадра нет дольше этого, а ролик ещё качается — буферизация. */
        const val STALL_MS = 400L
        /** Буферизация длится, пока не скачано столько мс ролика вперёд (по средней скорости)… */
        const val REFILL_MS = 2_000L
        /** …но не меньше стольких байт. */
        const val MIN_REFILL = 256L * 1024
    }
}

/** Часы воспроизведения: время ролика с паузами. Стоят, пока не запущены. */
/** Громкость куска PCM 16 бит LE: каждый отсчёт умножается на [gain]. */
internal fun scalePcm16(buffer: ByteArray, length: Int, gain: Float) {
    var i = 0
    while (i + 1 < length) {
        val sample = ((buffer[i].toInt() and 0xff) or (buffer[i + 1].toInt() shl 8)).toShort()
        val scaled = (sample * gain).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
        buffer[i] = scaled.toByte()
        buffer[i + 1] = (scaled shr 8).toByte()
        i += 2
    }
}

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

    /** Остановленные часы — назад к [ms] (не дальше, чем стоят). */
    @Synchronized
    fun rewind(ms: Long) {
        if (runningSince == null && ms < baseMs) baseMs = ms
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

    /**
     * Процесс ffmpeg. Ролик с 127.0.0.1 не должен уходить в системный прокси: ffmpeg берёт его
     * из `http_proxy` и не знает, что локальный адрес — исключение.
     */
    fun process(command: List<String>): ProcessBuilder = ProcessBuilder(command).apply {
        listOf("http_proxy", "HTTP_PROXY", "all_proxy", "ALL_PROXY").forEach(environment()::remove)
    }

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
