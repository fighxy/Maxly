package app.maxly.data.diagnostics

import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Bounded background writer. Reads/export/clear wait for previously accepted entries. */
class FileLog(
    val dir: File,
    private val maxBytes: Long = 512L * 1024,
    private val files: Int = 3,
    private val now: () -> Long = System::currentTimeMillis,
) : AutoCloseable {
    private val lock = Any()
    @Volatile private var writerThread: Thread? = null
    private val writer = java.util.concurrent.Executors.newSingleThreadExecutor { task ->
        Thread(task, "maxly-log").apply { isDaemon = true; writerThread = this }
    }
    private val pending = java.util.concurrent.atomic.AtomicInteger()
    private val dropped = java.util.concurrent.atomic.AtomicLong()

    fun flush() {
        if (Thread.currentThread() === writerThread) return
        runCatching { writer.submit {}.get(2, java.util.concurrent.TimeUnit.SECONDS) }
    }

    override fun close() { flush(); writer.shutdown() }

    private val current = File(dir, "app.log")

    fun append(level: Char, tag: String, message: String, error: Throwable? = null) {
        if (pending.incrementAndGet() > 512) {
            pending.decrementAndGet()
            dropped.incrementAndGet()
            return
        }
        val stamp = now()
        val bounded = if (tag == "diagnostic") message else message.take(16_384)
        // Capture only bounded stack frames; do not retain the Throwable/user payload in the queue.
        val trace = error?.let { it.javaClass.name + "\n" + it.stackTrace.take(32).joinToString("\n") { frame -> "at $frame" } }
        if (writer.isShutdown) { pending.decrementAndGet(); return }
        try { writer.execute {
            try {
                val lost = dropped.getAndSet(0)
                val line = buildString {
                    if (lost > 0) append(timestamp(stamp)).append(" W diagnostics: queue_dropped=").append(lost).append('\n')
                    if (tag == "diagnostic") append(bounded)
                    else append(timestamp(stamp)).append(' ').append(level).append(' ').append(tag).append(": ").append(bounded)
                    if (trace != null) append('\n').append(trace)
                    append('\n')
                }
                synchronized(lock) {
                    dir.mkdirs()
                    val bytes = line.toByteArray(Charsets.UTF_8)
                    if (current.exists() && current.length() + bytes.size > maxBytes) rotate()
                    current.appendBytes(bytes)
                }
            } catch (_: Exception) {
                // Logging must not crash the app when storage is unavailable.
            } finally { pending.decrementAndGet() }
        } } catch (_: java.util.concurrent.RejectedExecutionException) { pending.decrementAndGet() }
    }

    /** Файлы журнала от старых к новым. */
    fun parts(): List<File> {
        flush()
        return synchronized(lock) {
            ((files - 1) downTo 1).map { File(dir, "app.$it.log") }.plus(current).filter { it.exists() }
        }
    }

    /** Весь журнал одним текстом. */
    fun read(): String {
        flush()
        return synchronized(lock) {
            ((files - 1) downTo 1).map { File(dir, "app.$it.log") }.plus(current)
                .joinToString("") { runCatching { it.readText() }.getOrDefault("") }
        }
    }

    /** Последние [maxChars] символов журнала — для отчёта о сбое. */
    fun tail(maxChars: Int = 16_000): String {
        val text = read()
        if (text.length <= maxChars) return text
        val cut = text.takeLast(maxChars)
        return cut.substringAfter('\n', cut)
    }

    val isEmpty: Boolean get() = parts().all { it.length() == 0L }

    fun clear() {
        writer.submit { synchronized(lock) {
            ((files - 1) downTo 1).map { File(dir, "app.$it.log") }.plus(current).forEach { it.delete() }
        } }.get()
    }

    private fun rotate() {
        if (files <= 1) { current.delete(); return }
        File(dir, "app.${files - 1}.log").delete()
        for (index in files - 2 downTo 1) {
            val part = File(dir, "app.$index.log")
            if (part.exists()) part.renameTo(File(dir, "app.${index + 1}.log"))
        }
        current.renameTo(File(dir, "app.1.log"))
    }

    companion object {
        private val format = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSSxxx")

        /** Местное время с поясом: так строки журнала и отчёта сверяются со временем сбоя. */
        fun timestamp(ms: Long): String = format.format(Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()))

        fun stackTrace(error: Throwable): String = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
    }
}

/**
 * Журнал для всего приложения: строка уходит в файл ([file]) и в системный журнал
 * платформы ([echo]). До настройки строки только эхом.
 */
object AppLog {
    @Volatile
    var file: FileLog? = null

    @Volatile
    var echo: (level: Char, tag: String, message: String, error: Throwable?) -> Unit = { _, _, _, _ -> }

    fun i(tag: String, message: String) = write('I', tag, message, null)

    fun w(tag: String, message: String, error: Throwable? = null) = write('W', tag, message, error)

    fun e(tag: String, message: String, error: Throwable? = null) = write('E', tag, message, error)

    private fun write(level: Char, tag: String, message: String, error: Throwable?) {
        try {
            echo(level, tag, message, error)
        } catch (_: Exception) {
        }
        file?.append(level, tag, message, error)
    }
}
