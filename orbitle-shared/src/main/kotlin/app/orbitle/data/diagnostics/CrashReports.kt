package app.orbitle.data.diagnostics

import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** Один отчёт о сбое: файл `crash-<время>-<вид>.txt`, первая строка — заголовок. */
data class CrashReport(val name: String, val timeMs: Long, val kind: String, val title: String)

/**
 * Отчёты о сбоях на диске: пишутся синхронно, пока процесс ещё жив, читаются на следующем
 * запуске. Хранятся последние [keep].
 *
 * Виды: [CRASH] — необработанное исключение, [ERROR] — исключение, которое поймал обработчик
 * корутин, [NATIVE] и [ANR] — падение в нативном коде и зависание, о которых система
 * рассказала после перезапуска.
 */
class CrashReports(
    val dir: File,
    private val keep: Int = 20,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()

    /** Записать отчёт; `null`, если записать не вышло. */
    fun record(kind: String, title: String, body: String, timeMs: Long = now()): File? = synchronized(lock) {
        try {
            dir.mkdirs()
            var file = File(dir, "$PREFIX$timeMs-$kind.txt")
            var copy = 1
            while (file.exists()) file = File(dir, "$PREFIX$timeMs-$kind-${copy++}.txt")
            file.writeText(title.lineSequence().first().take(TITLE_LIMIT) + "\n" + body)
            prune()
            file
        } catch (_: Exception) {
            null
        }
    }

    /** Отчёт об исключении: время, поток, сведения о приложении, стек и хвост журнала. */
    fun recordError(
        kind: String,
        error: Throwable,
        thread: String?,
        info: String,
        logTail: String,
        timeMs: Long = now(),
    ): File? = record(kind, title(kind, error), body(kind, timeMs, thread, info, FileLog.stackTrace(error), logTail), timeMs)

    /** Отчёты от новых к старым. */
    fun list(): List<CrashReport> = synchronized(lock) {
        val files = dir.listFiles { file -> file.isFile && file.name.startsWith(PREFIX) && file.name.endsWith(".txt") }.orEmpty()
        files.mapNotNull(::parse).sortedWith(compareByDescending<CrashReport> { it.timeMs }.thenByDescending { it.name })
    }

    fun file(name: String): File? {
        if (!safe(name)) return null
        return File(dir, name).takeIf { it.isFile }
    }

    fun text(name: String): String? = synchronized(lock) { file(name)?.let { runCatching { it.readText() }.getOrNull() } }

    fun remove(name: String) = synchronized(lock) {
        file(name)?.delete()
        Unit
    }

    fun removeAll() = synchronized(lock) {
        list().forEach { File(dir, it.name).delete() }
    }

    private fun prune() {
        list().drop(keep).forEach { File(dir, it.name).delete() }
    }

    private fun parse(file: File): CrashReport? {
        val parts = file.name.removePrefix(PREFIX).removeSuffix(".txt").split('-')
        val time = parts.getOrNull(0)?.toLongOrNull() ?: return null
        val kind = parts.getOrNull(1).orEmpty()
        val title = runCatching { file.useLines { it.firstOrNull() } }.getOrNull().orEmpty()
        return CrashReport(file.name, time, kind, title)
    }

    private fun safe(name: String) = name.startsWith(PREFIX) && name.endsWith(".txt") && '/' !in name && '\\' !in name && ".." !in name

    companion object {
        const val CRASH = "crash"
        const val ERROR = "error"
        const val NATIVE = "native"
        const val ANR = "anr"
        private const val PREFIX = "crash-"
        private const val TITLE_LIMIT = 300

        fun title(kind: String, error: Throwable): String {
            val root = generateSequence(error) { it.cause.takeIf { cause -> cause !== it } }.last()
            val what = buildString {
                append(error.javaClass.name)
                error.message?.takeIf { it.isNotBlank() }?.let { append(": ").append(it.lineSequence().first()) }
                if (root !== error) append(" ← ").append(root.javaClass.name)
            }
            return "${kindTitle(kind)}: $what"
        }

        fun kindTitle(kind: String): String = when (kind) {
            CRASH -> "Сбой"
            ERROR -> "Ошибка"
            NATIVE -> "Сбой в нативном коде"
            ANR -> "Приложение зависло"
            else -> "Отчёт"
        }

        fun body(kind: String, timeMs: Long, thread: String?, info: String, details: String, logTail: String): String = buildString {
            append("Время: ").append(FileLog.timestamp(timeMs)).append('\n')
            append("Вид: ").append(kindTitle(kind)).append('\n')
            if (thread != null) append("Поток: ").append(thread).append('\n')
            if (info.isNotBlank()) append(info.trimEnd()).append('\n')
            append('\n').append(details.trimEnd()).append('\n')
            if (logTail.isNotBlank()) {
                append("\nЖурнал перед сбоем:\n").append(logTail.trimEnd()).append('\n')
            }
        }
    }
}

/**
 * Обработчик необработанных исключений: пишет отчёт и строку журнала, а потом отдаёт
 * исключение прежнему обработчику — тот и завершает процесс, как без нас.
 */
object CrashHandler {
    private val handling = AtomicBoolean(false)
    private var installed: Thread.UncaughtExceptionHandler? = null

    fun install(reports: CrashReports, log: FileLog?, info: () -> String) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        if (previous != null && previous === installed) return
        val handler = Thread.UncaughtExceptionHandler { thread, error ->
            // Повторный сбой внутри самого обработчика не пишется по кругу.
            if (handling.compareAndSet(false, true)) {
                try {
                    val details = try {
                        info()
                    } catch (_: Throwable) {
                        ""
                    }
                    reports.recordError(CrashReports.CRASH, error, thread.name, details, log?.tail().orEmpty())
                    log?.append('E', "crash", "Необработанное исключение в потоке ${thread.name}", error)
                } catch (_: Throwable) {
                } finally {
                    handling.set(false)
                }
            }
            if (previous != null) previous.uncaughtException(thread, error) else error.printStackTrace()
        }
        installed = handler
        Thread.setDefaultUncaughtExceptionHandler(handler)
    }
}
