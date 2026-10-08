package app.orbitle.data.diagnostics

import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Журнал приложения в файлах `app.log`, `app.1.log`, …: каждая строка сразу пишется на диск,
 * чтобы журнал пережил падение процесса. Когда текущий файл дорастает до [maxBytes], он
 * становится `app.1.log`, а самый старый удаляется.
 */
class FileLog(
    val dir: File,
    private val maxBytes: Long = 512L * 1024,
    private val files: Int = 3,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()
    private val current = File(dir, "app.log")

    fun append(level: Char, tag: String, message: String, error: Throwable? = null) {
        val line = buildString {
            append(timestamp(now())).append(' ').append(level).append(' ').append(tag).append(": ").append(message)
            if (error != null) append('\n').append(stackTrace(error).trimEnd())
            append('\n')
        }
        synchronized(lock) {
            try {
                dir.mkdirs()
                if (current.exists() && current.length() + line.length > maxBytes) rotate()
                current.appendText(line)
            } catch (_: Exception) {
                // Журнал не должен ронять приложение: нет места — строка теряется.
            }
        }
    }

    /** Файлы журнала от старых к новым. */
    fun parts(): List<File> = synchronized(lock) {
        ((files - 1) downTo 1).map { File(dir, "app.$it.log") }.plus(current).filter { it.exists() }
    }

    /** Весь журнал одним текстом. */
    fun read(): String = synchronized(lock) {
        parts().joinToString("") { runCatching { it.readText() }.getOrDefault("") }
    }

    /** Последние [maxChars] символов журнала — для отчёта о сбое. */
    fun tail(maxChars: Int = 16_000): String {
        val text = read()
        if (text.length <= maxChars) return text
        val cut = text.takeLast(maxChars)
        return cut.substringAfter('\n', cut)
    }

    val isEmpty: Boolean get() = parts().all { it.length() == 0L }

    fun clear() = synchronized(lock) {
        parts().forEach { it.delete() }
    }

    private fun rotate() {
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
