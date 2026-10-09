package app.maxly.media

import app.maxly.data.StorageRepository
import app.maxly.domain.OutgoingFile
import app.maxly.domain.StorageCategory
import app.maxly.domain.StorageUsage
import app.maxly.domain.VoiceRecording
import app.maxly.platform.AppPaths
import app.maxly.platform.DesktopActions
import app.maxly.presentation.chat.MediaSaver
import app.maxly.presentation.chat.SavedKind
import app.maxly.presentation.chat.VoicePlayback
import app.maxly.presentation.chat.VoicePlayer
import app.maxly.presentation.chat.VoiceWave
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.imageio.ImageIO
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioInputStream
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.DataLine
import javax.sound.sampled.SourceDataLine
import javax.sound.sampled.TargetDataLine
import kotlin.coroutines.coroutineContext
import kotlin.math.sqrt

/** Размеры кэша по папкам. Картинки Coil лежат в `image_cache`. */
class CacheStorage(private val root: File = AppPaths.cacheDir) : StorageRepository {
    override suspend fun usage(): StorageUsage = withContext(Dispatchers.IO) {
        StorageUsage(
            mapOf(
                StorageCategory.PHOTOS to size(File(root, IMAGES)),
                StorageCategory.FILES to size(File(root, FILES)),
                StorageCategory.OUTGOING to size(File(root, OUTGOING)),
                StorageCategory.OTHER to others().sumOf(::size),
            ),
        )
    }

    override suspend fun clear(categories: Set<StorageCategory>) = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        categories.forEach { category ->
            when (category) {
                StorageCategory.PHOTOS -> File(root, IMAGES).deleteRecursively()
                StorageCategory.FILES -> File(root, FILES).listFiles()?.forEach { it.deleteRecursively() }
                StorageCategory.OUTGOING -> File(root, OUTGOING).listFiles()
                    ?.filter { now - it.lastModified() > BUSY_MS }
                    ?.forEach { it.deleteRecursively() }
                StorageCategory.OTHER -> others().forEach { it.deleteRecursively() }
            }
        }
    }

    private fun others(): List<File> = root.listFiles().orEmpty().filter { it.name !in setOf(IMAGES, FILES, OUTGOING) }

    private fun size(file: File): Long = when {
        file.isFile -> file.length()
        file.isDirectory -> file.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        else -> 0L
    }

    private companion object {
        const val IMAGES = "image_cache"
        const val FILES = "files"
        const val OUTGOING = "outgoing"
        const val BUSY_MS = 10 * 60_000L
    }
}

/** Скачивание вложений в кэш. Повторно уже лежащий файл не качается. */
class FileDownloader(private val userAgent: () -> String, root: File = File(AppPaths.cacheDir, "files")) {
    private val root = root.apply { mkdirs() }
    private val http = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()

    fun cached(fileId: String, name: String): File? = target(fileId, name).takeIf { it.isFile && it.length() > 0 }

    suspend fun download(url: String, fileId: String, name: String, progress: (Float) -> Unit = {}): File = withContext(Dispatchers.IO) {
        cached(fileId, name)?.let { return@withContext it }
        val target = target(fileId, name)
        target.parentFile?.mkdirs()
        val partial = File(target.parentFile, target.name + ".part")
        val request = Request.Builder().url(url).header("User-Agent", userAgent()).build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
            val body = response.body ?: throw IOException("empty body")
            val total = body.contentLength()
            body.byteStream().use { input ->
                partial.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    while (true) {
                        coroutineContext.ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        done += read
                        if (total > 0) progress((done.toFloat() / total).coerceIn(0f, 1f))
                    }
                }
            }
        }
        if (!partial.renameTo(target)) throw IOException("rename failed")
        target
    }

    private fun target(fileId: String, name: String): File {
        val safe = name.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_").trim().ifEmpty { "file" }.take(120)
        return File(File(root, fileId.replace(Regex("[^A-Za-z0-9_-]"), "_")), safe)
    }
}

/** «Сохранить» кладёт копию в «Загрузки» пользователя. */
class DownloadsSaver : MediaSaver {
    override suspend fun save(path: String, name: String, kind: SavedKind) {
        withContext(Dispatchers.IO) {
            val source = File(path)
            val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "Orbitle" }
            var target = File(AppPaths.downloads, safe)
            var index = 2
            while (target.exists()) {
                val dot = safe.lastIndexOf('.')
                val next = if (dot > 0) safe.substring(0, dot) + " $index" + safe.substring(dot) else "$safe $index"
                target = File(AppPaths.downloads, next)
                index += 1
            }
            source.copyTo(target, overwrite = false)
        }
    }
}

/** Выбранные файлы копируются в кэш: ядро читает вложение по обычному пути. */
object AttachmentImporter {
    suspend fun import(files: List<File>): List<OutgoingFile> = withContext(Dispatchers.IO) {
        files.mapNotNull { file -> runCatching { importOne(file) }.getOrNull() }
    }

    private fun importOne(file: File): OutgoingFile? {
        if (!file.isFile) return null
        val ext = file.extension.lowercase()
        val mime = when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "mp4", "m4v", "mov", "webm" -> "video/$ext"
            else -> null
        }
        val kind = OutgoingFile.kindOf(mime)
        val safe = file.name.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_").trim().ifEmpty { "file" }.take(120)
        val target = File(File(AppPaths.cacheDir, "outgoing/${UUID.randomUUID()}"), safe)
        target.parentFile?.mkdirs()
        file.copyTo(target, overwrite = true)
        var width: Int? = null
        var height: Int? = null
        if (kind == OutgoingFile.Kind.PHOTO) {
            val image = ImageIO.read(target)
            width = image?.width?.takeIf { it > 0 }
            height = image?.height?.takeIf { it > 0 }
        }
        return OutgoingFile(target.absolutePath, safe, kind, target.length(), width, height)
    }
}

/**
 * Голосовые: файл декодируется ffmpeg в PCM и играет через Java Sound.
 * Пауза и перемотка перезапускают декодер с нужной секунды.
 */
class DesktopVoicePlayer(private val scope: CoroutineScope, private val downloader: FileDownloader) : VoicePlayer {
    private val _playback = MutableStateFlow<VoicePlayback?>(null)
    override val playback: StateFlow<VoicePlayback?> = _playback.asStateFlow()

    private var job: Job? = null
    private var process: Process? = null
    private var line: SourceDataLine? = null

    override fun play(messageId: String, voiceId: String, url: String, durationMs: Long, from: Float?) {
        val current = _playback.value
        val resume = from == null && current?.matches(messageId, voiceId) == true && !current.isPlaying
        val fraction = from ?: if (resume) current.progress else 0f
        stopPlayback(clear = false)
        _playback.value = VoicePlayback(messageId, voiceId, isPlaying = false, positionMs = (durationMs * fraction).toLong(), durationMs = durationMs, isBuffering = true)
        job = scope.launch(Dispatchers.IO) {
            val file = runCatching { materialize(url, voiceId) }.getOrNull()
            if (file == null) {
                _playback.value = null
                return@launch
            }
            runCatching { pump(messageId, voiceId, file, durationMs, fraction) }
            if (_playback.value?.matches(messageId, voiceId) == true && _playback.value?.isPlaying != true) {
                // Остановлено паузой: состояние уже записано.
            }
        }
    }

    override fun pause() {
        val current = _playback.value ?: return
        stopPlayback(clear = false)
        _playback.value = current.copy(isPlaying = false, isBuffering = false)
    }

    override fun seek(fraction: Float) {
        val current = _playback.value ?: return
        play(current.messageId, current.voiceId, currentUrl(current.voiceId) ?: return, current.durationMs, fraction.coerceIn(0f, 1f))
    }

    override fun stop() = stopPlayback(clear = true)

    private val urls = mutableMapOf<String, String>()

    private fun currentUrl(voiceId: String): String? = urls[voiceId]

    private suspend fun materialize(url: String, voiceId: String): File {
        urls[voiceId] = url
        if (url.startsWith("file:")) return File(java.net.URI(url))
        val local = File(url)
        if (local.isFile) return local
        return downloader.download(url, "voice-$voiceId", "voice.audio")
    }

    private fun pump(messageId: String, voiceId: String, file: File, durationMs: Long, from: Float) {
        val startSec = (durationMs * from.coerceIn(0f, 0.99f) / 1000.0)
        val ffmpeg = ProcessBuilder(
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-ss", startSec.toString(), "-i", file.absolutePath,
            "-f", "s16le", "-ac", "1", "-ar", "48000", "-",
        ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        process = ffmpeg
        val format = AudioFormat(48_000f, 16, 1, true, false)
        val speaker = AudioSystem.getLine(DataLine.Info(SourceDataLine::class.java, format)) as SourceDataLine
        speaker.open(format)
        speaker.start()
        line = speaker
        val started = System.currentTimeMillis() - (durationMs * from).toLong()
        _playback.value = VoicePlayback(messageId, voiceId, true, (durationMs * from).toLong(), durationMs)
        val buffer = ByteArray(4096)
        val input = ffmpeg.inputStream
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            speaker.write(buffer, 0, read)
            val position = (System.currentTimeMillis() - started).coerceAtMost(durationMs)
            _playback.value = VoicePlayback(messageId, voiceId, true, position, durationMs)
        }
        speaker.drain()
        val still = _playback.value?.matches(messageId, voiceId) == true && _playback.value?.isPlaying == true
        stopPlayback(clear = false)
        if (still) _playback.value = null
    }

    private fun stopPlayback(clear: Boolean) {
        job?.cancel()
        job = null
        runCatching { process?.destroyForcibly() }
        process = null
        runCatching { line?.stop(); line?.close() }
        line = null
        if (clear) _playback.value = null
    }
}

/**
 * Микрофон через Java Sound (WAV), затем ffmpeg собирает Ogg/Opus, как у телефона.
 * Уровень для волны снимается 10 раз в секунду.
 */
class DesktopVoiceRecorder(private val scope: CoroutineScope) {
    data class Live(val elapsedMs: Long = 0, val level: Float = 0f)

    private val _live = MutableStateFlow<Live?>(null)
    val live: StateFlow<Live?> = _live.asStateFlow()

    private var line: TargetDataLine? = null
    private var wav: File? = null
    private var startedAt = 0L
    private val peaks = mutableListOf<Float>()
    private var ticker: Job? = null
    private var writer: Job? = null

    val isRecording: Boolean get() = line != null

    fun start(): Boolean {
        if (line != null) return true
        val format = AudioFormat(48_000f, 16, 1, true, false)
        val folder = File(AppPaths.cacheDir, "outgoing/voice").apply { mkdirs() }
        val target = File(folder, "voice-${System.currentTimeMillis()}.wav")
        return try {
            val mic = AudioSystem.getLine(DataLine.Info(TargetDataLine::class.java, format)) as TargetDataLine
            mic.open(format)
            mic.start()
            line = mic
            wav = target
            startedAt = System.currentTimeMillis()
            peaks.clear()
            _live.value = Live()
            writer = scope.launch(Dispatchers.IO) {
                val stream = AudioInputStream(mic)
                runCatching { AudioSystem.write(stream, javax.sound.sampled.AudioFileFormat.Type.WAVE, target) }
            }
            ticker = scope.launch {
                val sample = ByteArray(4_800)
                while (isActive && line != null) {
                    delay(100)
                    val current = line ?: break
                    val read = current.read(sample, 0, sample.size)
                    var sum = 0.0
                    var count = 0
                    var i = 0
                    while (i + 1 < read) {
                        val value = (sample[i].toInt() and 0xff) or (sample[i + 1].toInt() shl 8)
                        sum += value * value
                        count += 1
                        i += 2
                    }
                    val rms = if (count == 0) 0.0 else sqrt(sum / count)
                    val peak = VoiceWave.peak((rms / 32.0).toInt().coerceIn(0, 32767))
                    peaks += peak
                    _live.value = Live(System.currentTimeMillis() - startedAt, VoiceWave.normalized(peak))
                }
            }
            true
        } catch (_: Exception) {
            target.delete()
            false
        }
    }

    fun finish(minimumMs: Long): VoiceRecording? {
        val target = wav
        val duration = System.currentTimeMillis() - startedAt
        stopLine()
        if (target == null || duration < minimumMs || !target.exists() || target.length() == 0L) {
            target?.delete()
            return null
        }
        val ogg = File(target.parentFile, target.nameWithoutExtension + ".ogg")
        val converted = runCatching {
            val code = ProcessBuilder(
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", target.absolutePath, "-c:a", "libopus", "-b:a", "32k", "-ac", "1", "-ar", "48000", ogg.absolutePath,
            ).redirectError(ProcessBuilder.Redirect.DISCARD).start().waitFor()
            code == 0 && ogg.length() > 0
        }.getOrDefault(false)
        val file = if (converted) {
            target.delete()
            ogg
        } else {
            ogg.delete()
            target
        }
        return VoiceRecording(file.absolutePath, duration, VoiceWave.wave(peaks.toList()), if (converted) "voice.ogg" else "voice.wav")
    }

    fun cancel() {
        val target = wav
        stopLine()
        target?.delete()
    }

    private fun stopLine() {
        ticker?.cancel()
        ticker = null
        val current = line
        line = null
        _live.value = null
        runCatching { current?.stop(); current?.close() }
        val writing = writer
        runCatching { kotlinx.coroutines.runBlocking { writing?.join() } }
        writer = null
        wav = null
    }
}

/** Локальный или удалённый ролик для внешнего проигрывателя. */
object DesktopVideo {
    suspend fun materialize(url: String, userAgent: String): File = withContext(Dispatchers.IO) {
        if (url.startsWith("file:")) return@withContext File(java.net.URI(url))
        val local = File(url)
        if (local.isFile) return@withContext local
        FileDownloader({ userAgent }).download(url, "video-${url.hashCode()}", "video.mp4")
    }

    fun play(file: File) = DesktopActions.openFile(file)
}
