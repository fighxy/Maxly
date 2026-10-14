package app.maxly.media

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.BufferedReader
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.InputStreamReader
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Ответ источника: байты с [offset] (0 — сервер не умеет диапазоны), [total] — размер ролика или −1. */
internal class UpstreamBody(val input: InputStream, val offset: Long, val total: Long, private val onClose: () -> Unit) : AutoCloseable {
    override fun close() = onClose()
}

/** Откуда качается ролик: целиком или с байта. */
internal fun interface VideoUpstream {
    fun open(from: Long): UpstreamBody
}

/** Ролик с CDN по HTTP; [from] больше нуля — запрос диапазона. */
internal class HttpUpstream(private val url: String, private val userAgent: String) : VideoUpstream {
    override fun open(from: Long): UpstreamBody {
        val request = Request.Builder().url(url).header("User-Agent", userAgent)
            .apply { if (from > 0) header("Range", "bytes=$from-") }
            .build()
        val response = http.newCall(request).execute()
        if (!response.isSuccessful) {
            response.close()
            throw IOException("HTTP ${response.code}")
        }
        val body = response.body ?: run {
            response.close()
            throw IOException("empty body")
        }
        val (offset, total) = if (response.code == 206) {
            val range = response.header("Content-Range").orEmpty()
            (RANGE.find(range)?.groupValues?.get(1)?.toLongOrNull() ?: from) to (range.substringAfter('/', "").toLongOrNull() ?: -1L)
        } else {
            0L to body.contentLength()
        }
        return UpstreamBody(body.byteStream(), offset, total) { response.close() }
    }

    private companion object {
        val RANGE = Regex("""bytes\s+(\d+)-""")
        val http: OkHttpClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()
    }
}

/**
 * Ролик, который качается в кэш ([target]) и тем временем читается проигрывателем. Скачанное
 * лежит в `.stream`-файле; [readAt] отдаёт его и ждёт, если просят дальше.
 */
internal class StreamingDownload(private val upstream: VideoUpstream, val target: File) {
    private val partial = File(target.parentFile, target.name + ".stream")
    private val lock = Object()

    @Volatile var total = -1L
        private set
    @Volatile var done = 0L
        private set
    @Volatile var finished = false
        private set
    @Volatile var failure: Throwable? = null
        private set
    /** Известен размер, ролик скачан или загрузка не удалась: дальше можно решать, как играть. */
    val ready: Boolean get() = total >= 0 || finished || failure != null || cancelled

    @Volatile private var cancelled = false
    @Volatile private var body: UpstreamBody? = null
    /** Источник не отдаёт диапазоны: дальнее место ждёт загрузку. */
    @Volatile private var noRanges = false

    private val _progress = MutableStateFlow(0f)
    /** Скачанная доля 0…1. */
    val progress: StateFlow<Float> = _progress.asStateFlow()

    /** Качает до конца в текущем потоке; ошибка остаётся в [failure]. */
    fun run() {
        try {
            target.parentFile?.mkdirs()
            val opened = upstream.open(0)
            body = opened
            opened.use {
                if (cancelled) throw IOException("cancelled")
                if (opened.offset != 0L) throw IOException("range from ${opened.offset}")
                synchronized(lock) {
                    total = opened.total
                    lock.notifyAll()
                }
                partial.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = opened.input.read(buffer)
                        if (read < 0) break
                        if (cancelled) throw IOException("cancelled")
                        out.write(buffer, 0, read)
                        synchronized(lock) {
                            done += read
                            lock.notifyAll()
                        }
                        val size = total
                        if (size > 0) _progress.value = (done.toFloat() / size).coerceIn(0f, 1f)
                    }
                }
            }
            if (cancelled) throw IOException("cancelled")
            if (total > 0 && done != total) throw IOException("short body: $done of $total")
            synchronized(lock) {
                target.delete()
                if (!partial.renameTo(target)) {
                    partial.copyTo(target, overwrite = true)
                    partial.delete()
                }
                total = done
                finished = true
                lock.notifyAll()
            }
            _progress.value = 1f
        } catch (e: Throwable) {
            synchronized(lock) {
                failure = e
                lock.notifyAll()
            }
            partial.delete()
        } finally {
            body = null
        }
    }

    /** Останавливает загрузку; ждущие читатели получают ошибку. */
    fun cancel() {
        cancelled = true
        runCatching { body?.close() }
        synchronized(lock) { lock.notifyAll() }
    }

    /** Ждёт, пока станет ясен размер (или ролик скачается, или загрузка упадёт). */
    suspend fun awaitReady() {
        while (!ready) delay(20)
    }

    suspend fun awaitFinished(): Boolean {
        while (!finished && failure == null && !cancelled) delay(100)
        return finished
    }

    /** Дальнее место ([pos] заметно дальше скачанного) лучше взять у источника отдельным запросом. */
    fun isFar(pos: Long): Boolean = !finished && !noRanges && pos > done + AHEAD

    /** Читает скачанное с [pos] в [buffer]. Пока байтов нет — ждёт. −1 — конец ролика. */
    fun readAt(pos: Long, buffer: ByteArray): Int = synchronized(lock) {
        while (true) {
            if (cancelled) throw IOException("cancelled")
            if (finished) break
            failure?.let { throw IOException("download failed", it) }
            if (total in 0..pos) return -1
            if (done > pos) break
            lock.wait(50)
        }
        val file = if (finished) target else partial
        val limit = if (finished) file.length() else done
        if (pos >= limit) return -1
        RandomAccessFile(file, "r").use { raf ->
            raf.seek(pos)
            raf.read(buffer, 0, minOf(buffer.size.toLong(), limit - pos).toInt())
        }
    }

    /** Диапазон прямо у источника; null — источник диапазоны не отдаёт (дальше ждём загрузку). */
    fun openUpstream(pos: Long): UpstreamBody? {
        val opened = upstream.open(pos)
        if (opened.offset != pos) {
            opened.close()
            noRanges = true
            return null
        }
        return opened
    }

    companion object {
        /** Дальше скачанного на столько — отдельный запрос к источнику, а не ожидание. */
        const val AHEAD = 2L * 1024 * 1024
    }
}

/**
 * HTTP на 127.0.0.1 для ffmpeg: отдаёт [StreamingDownload] с поддержкой `Range`, чтобы ролик
 * играл и перематывался, пока качается. Один запрос — одно соединение (`Connection: close`).
 */
internal object LocalVideoServer {
    private val streams = ConcurrentHashMap<String, StreamingDownload>()

    private val server: ServerSocket by lazy {
        ServerSocket(0, 50, InetAddress.getLoopbackAddress()).also { socket ->
            thread(isDaemon = true, name = "maxly-video-server") {
                while (!socket.isClosed) {
                    val client = runCatching { socket.accept() }.getOrNull() ?: continue
                    thread(isDaemon = true, name = "maxly-video-client") { client.use(::serve) }
                }
            }
        }
    }

    fun register(stream: StreamingDownload): String {
        val token = UUID.randomUUID().toString()
        streams[token] = stream
        return "http://127.0.0.1:${server.localPort}/v/$token"
    }

    fun unregister(url: String) {
        streams.remove(url.substringAfterLast('/'))
    }

    private fun serve(socket: Socket) {
        val input = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
        val out = socket.getOutputStream()
        val requestLine = input.readLine() ?: return
        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = input.readLine() ?: return
            if (line.isEmpty()) break
            val colon = line.indexOf(':')
            if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
        }
        val parts = requestLine.split(' ')
        val method = parts.getOrNull(0).orEmpty()
        val stream = parts.getOrNull(1)?.takeIf { it.startsWith("/v/") }?.let { streams[it.removePrefix("/v/")] }
        if (stream == null || (method != "GET" && method != "HEAD")) return respond(out, "404 Not Found")
        runCatching { kotlinx.coroutines.runBlocking { stream.awaitReady() } }
        val total = stream.total
        if (total < 0) return respond(out, "503 Service Unavailable")
        val range = ByteRange.parse(headers["range"], total)
        if (range == null) {
            return respond(out, "416 Range Not Satisfiable", "Content-Range: bytes */$total")
        }
        val partial = headers["range"] != null
        val head = buildString {
            append(if (partial) "HTTP/1.1 206 Partial Content\r\n" else "HTTP/1.1 200 OK\r\n")
            append("Content-Type: video/mp4\r\nAccept-Ranges: bytes\r\n")
            if (partial) append("Content-Range: bytes ${range.first}-${range.last}/$total\r\n")
            append("Content-Length: ${range.last - range.first + 1}\r\nConnection: close\r\n\r\n")
        }
        out.write(head.toByteArray(Charsets.ISO_8859_1))
        if (method == "HEAD") return out.flush()
        runCatching { send(stream, range, out) }
        runCatching { out.flush() }
    }

    /** Байты [range]: скачанное — из файла, дальнее — прямо у источника. */
    private fun send(stream: StreamingDownload, range: LongRange, out: OutputStream) {
        val buffer = ByteArray(64 * 1024)
        var pos = range.first
        while (pos <= range.last) {
            if (stream.isFar(pos)) {
                val direct = runCatching { stream.openUpstream(pos) }.getOrNull()
                if (direct != null) {
                    direct.use { copy(it.input, out, range.last - pos + 1, buffer) }
                    return
                }
            }
            val read = stream.readAt(pos, buffer)
            if (read < 0) return
            val count = minOf(read.toLong(), range.last - pos + 1).toInt()
            out.write(buffer, 0, count)
            pos += count
        }
    }

    private fun copy(input: InputStream, out: OutputStream, length: Long, buffer: ByteArray) {
        var left = length
        while (left > 0) {
            val read = input.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
            if (read < 0) return
            out.write(buffer, 0, read)
            left -= read
        }
    }

    private fun respond(out: OutputStream, status: String, header: String? = null) {
        val extra = header?.let { "$it\r\n" }.orEmpty()
        out.write("HTTP/1.1 $status\r\n${extra}Content-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
        out.flush()
    }
}

/** Заголовок `Range: bytes=…` для ролика размером [total]. */
internal object ByteRange {
    /** Без заголовка — весь ролик; непонятный — тоже весь; за пределами — null (416). */
    fun parse(header: String?, total: Long): LongRange? {
        val whole = 0L..(total - 1)
        val spec = header?.trim()?.removePrefix("bytes=")?.substringBefore(',')?.trim() ?: return whole.takeIf { total > 0 }
        val dash = spec.indexOf('-')
        if (dash < 0) return whole
        val from = spec.substring(0, dash).trim()
        val to = spec.substring(dash + 1).trim()
        val range = when {
            from.isEmpty() -> to.toLongOrNull()?.let { maxOf(0, total - it)..(total - 1) } ?: return whole
            else -> {
                val start = from.toLongOrNull() ?: return whole
                val end = to.toLongOrNull()?.coerceAtMost(total - 1) ?: (total - 1)
                start..end
            }
        }
        return range.takeIf { it.first < total && it.first <= it.last }
    }
}
