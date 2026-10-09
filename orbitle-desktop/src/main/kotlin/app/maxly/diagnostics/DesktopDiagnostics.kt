package app.maxly.diagnostics

import app.maxly.BuildConfig
import app.maxly.data.calls.CallLog
import app.maxly.data.diagnostics.AppLog
import app.maxly.data.diagnostics.CrashHandler
import app.maxly.data.diagnostics.CrashReports
import app.maxly.data.diagnostics.FileLog
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineName
import java.awt.EventQueue
import java.io.File
import java.io.OutputStream
import java.io.PrintStream
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.Collections

/**
 * Журнал и отчёты о сбоях на компьютере. Включается первой строкой `main`:
 * - журнал — `~/.orbitle/logs/app.log` (до пяти файлов по мегабайту), туда же уходят
 *   `System.out` и `System.err`: у установленного приложения Windows консоли нет;
 * - отчёты — `~/.orbitle/crashes`: необработанные исключения, ошибки корутин, зависания окна
 *   со стеками всех потоков ([UiWatchdog]) и запуски, которые не завершились штатно (процесс
 *   сняли из диспетчера задач или он упал в нативном коде).
 *
 * Оба показывает экран «О приложении».
 */
object DesktopDiagnostics {
    private const val TAG = "app"
    private const val LOG_BYTES = 1024L * 1024
    private const val LOG_FILES = 5
    private const val NATIVE_LIMIT = 64 * 1024

    @Volatile
    var log: FileLog? = null
        private set

    @Volatile
    var reports: CrashReports? = null
        private set

    private val reported = Collections.synchronizedSet(HashSet<String>())
    private var runLock: FileLock? = null
    private var runFile: RandomAccessFile? = null
    private var runLine = ""
    private var watchdog: Thread? = null

    fun init(home: File) {
        if (log != null) return
        val log = FileLog(File(home, "logs"), maxBytes = LOG_BYTES, files = LOG_FILES)
        val reports = CrashReports(File(home, "crashes"))
        this.log = log
        this.reports = reports
        val console = System.err
        AppLog.echo = { level, tag, message, error ->
            console.println("$level $tag: $message")
            error?.printStackTrace(console)
        }
        AppLog.file = log
        CrashHandler.install(reports, log) { info() }
        // Звонки пишут в общий журнал с тегом calls, стек ошибки — отдельной строкой.
        CallLog.sink = { level, message -> if (level == 'W') AppLog.w(CallLog.TAG, message) else AppLog.i(CallLog.TAG, message) }
        // Хвост журнала ещё от прошлого запуска: сначала — чем он кончился.
        try {
            checkPreviousRun(home, reports, log)
        } catch (e: Exception) {
            AppLog.w(TAG, "Не проверил прошлый запуск", e)
        }
        teeConsole(log)
        AppLog.i(TAG, "Запуск. " + info().replace('\n', ' '))
    }

    /** Версия, сборка, ОС и Java — в начало отчёта и в строку запуска. */
    fun info(): String = buildString {
        append("Orbitle ").append(BuildConfig.VERSION_NAME).append(", сборка ").append(BuildConfig.BUILD_SHA)
            .append(", ядро ").append(BuildConfig.CORE_REVISION).append('\n')
        append(System.getProperty("os.name")).append(' ').append(System.getProperty("os.version"))
            .append(" (").append(System.getProperty("os.arch")).append("), Java ")
            .append(System.getProperty("java.runtime.version") ?: System.getProperty("java.version"))
            .append(' ').append(System.getProperty("java.vendor").orEmpty())
        val runtime = Runtime.getRuntime()
        append(", память ").append(runtime.maxMemory() / (1024 * 1024)).append(" МБ, ядер ").append(runtime.availableProcessors())
    }

    /**
     * Обработчик корутин приложения: исключение, которое раньше роняло процесс, пишется в журнал
     * и в отчёт (один отчёт на одно место за запуск), а приложение живёт дальше.
     */
    val coroutineHandler = CoroutineExceptionHandler { context, error ->
        nonFatal("корутина ${context[CoroutineName]?.name.orEmpty()}".trim(), error)
    }

    fun nonFatal(where: String, error: Throwable) {
        AppLog.e(TAG, "Необработанная ошибка ($where)", error)
        val signature = error.javaClass.name + "@" + error.stackTrace.firstOrNull()
        if (!reported.add(signature)) return
        reports?.recordError(CrashReports.ERROR, error, Thread.currentThread().name, info(), log?.tail().orEmpty())
    }

    /** Сторож окна: подтормаживания — строкой в журнал, зависание — отчётом со стеками потоков. */
    fun watchUi() {
        if (watchdog != null) return
        val dog = UiWatchdog(
            post = EventQueue::invokeLater,
            now = { System.nanoTime() / 1_000_000 },
            onSlow = { AppLog.w("ui", "Окно не отвечало $it мс") },
            onHang = {
                markHung(true)
                recordHang(it)
            },
            onRecovered = {
                markHung(false)
                AppLog.w("ui", "Окно снова отвечает, зависание длилось $it мс")
            },
        )
        watchdog = dog.start()
    }

    /** Штатный выход: следующий запуск не сочтёт этот аварийным. */
    fun markCleanExit(home: File) {
        AppLog.i(TAG, "Выход")
        runCatching {
            synchronized(this) {
                runLock?.release()
                runFile?.close()
                runLock = null
                runFile = null
            }
            File(home, RUN_MARK).delete()
        }
    }

    /** Висит ли окно прямо сейчас — в отметку запуска: снятый в это время процесс уже описан отчётом о зависании. */
    @Synchronized
    private fun markHung(hung: Boolean) {
        val file = runFile ?: return
        runCatching {
            file.setLength(0)
            file.write("$runLine hung=${if (hung) 1 else 0}\n".toByteArray())
        }
    }

    private fun recordHang(waitedMs: Long) {
        val dump = ThreadDump.capture()
        val title = "${CrashReports.kindTitle(CrashReports.ANR)}: окно не отвечает больше ${waitedMs / 1000} с"
        AppLog.e("ui", "$title. Стеки потоков:\n$dump")
        val tail = log?.tail().orEmpty()
        reports?.record(CrashReports.ANR, title, CrashReports.body(CrashReports.ANR, System.currentTimeMillis(), null, info(), "Стеки потоков:\n$dump", tail))
    }

    /**
     * Отметка `running` живёт, пока работает процесс, и держит блокировку файла. Если на старте
     * отметка есть, а блокировки нет, прошлый процесс не дошёл до штатного выхода. Тогда пишется
     * отчёт, если процесс сняли не во время зависания окна: о нём уже написал сторож.
     */
    private fun checkPreviousRun(home: File, reports: CrashReports, log: FileLog) {
        val mark = File(home, RUN_MARK)
        val existed = mark.exists()
        val previous = if (existed) runCatching { mark.readText().trim() }.getOrDefault("") else ""
        val file = RandomAccessFile(mark, "rw")
        val lock = runCatching { file.channel.tryLock() }.getOrNull()
        if (lock == null) {
            file.close()
            AppLog.w(TAG, "Orbitle уже запущен в другом процессе")
            return
        }
        runLock = lock
        runFile = file
        runLine = "pid=${ProcessHandle.current().pid()} started=${System.currentTimeMillis()}"
        markHung(false)
        Runtime.getRuntime().addShutdownHook(Thread({ markCleanExit(home) }, "orbitle-exit"))
        if (!existed) return
        val started = previous.substringAfter("started=", "").substringBefore(' ').toLongOrNull()
        val native = nativeCrashLog(started)
        // Процесс сняли, пока окно висело: отчёт о зависании со стеками уже есть.
        val alreadyReported = "hung=1" in previous
        AppLog.w(TAG, "Прошлый запуск ($previous) не завершился штатно" + if (native != null) ": сбой JVM, ${native.name}" else "")
        if (alreadyReported && native == null) return
        val title = if (native != null) "${CrashReports.kindTitle(CrashReports.NATIVE)}: ${native.name}" else "${CrashReports.kindTitle(CrashReports.UNCLEAN)}: прошлый запуск не дошёл до выхода"
        val details = buildString {
            append("Процесс не дошёл до штатного выхода: его сняли из диспетчера задач, он упал в нативном коде или выключилось питание.\n")
            append("Отметка запуска: ").append(previous.ifEmpty { "—" }).append('\n')
            native?.let { append("\n").append(runCatching { it.readText().take(NATIVE_LIMIT) }.getOrDefault("")) }
        }
        val kind = if (native != null) CrashReports.NATIVE else CrashReports.UNCLEAN
        reports.record(kind, title, CrashReports.body(kind, System.currentTimeMillis(), null, info(), details, log.tail()))
    }

    /** Журнал сбоя JVM (`hs_err_pid*.log`) прошлого запуска: JVM кладёт его в рабочую папку. */
    private fun nativeCrashLog(since: Long?): File? {
        val dirs = listOfNotNull(System.getProperty("user.dir"), System.getProperty("java.io.tmpdir")).map(::File)
        return dirs.flatMap { dir -> dir.listFiles { f -> f.isFile && f.name.startsWith("hs_err_pid") && f.name.endsWith(".log") }.orEmpty().toList() }
            .filter { since == null || it.lastModified() >= since }
            .maxByOrNull { it.lastModified() }
    }

    /** `System.out` и `System.err` построчно в журнал и, как прежде, в консоль. */
    private fun teeConsole(log: FileLog) {
        System.setOut(PrintStream(LineTee(System.out) { log.append('I', "stdout", it) }, true, Charsets.UTF_8))
        System.setErr(PrintStream(LineTee(System.err) { log.append('W', "stderr", it) }, true, Charsets.UTF_8))
    }

    private const val RUN_MARK = "running"
}

/**
 * Поток, который пишет всё в [target] и отдаёт [line] каждую законченную строку.
 * Строки длиннее [limit] режутся, чтобы бесконечный вывод без перевода строки не съел память.
 */
internal class LineTee(
    private val target: OutputStream,
    private val limit: Int = 8_192,
    private val line: (String) -> Unit,
) : OutputStream() {
    private val buffer = java.io.ByteArrayOutputStream()

    @Synchronized
    override fun write(b: Int) {
        target.write(b)
        accept(b)
    }

    @Synchronized
    override fun write(b: ByteArray, off: Int, len: Int) {
        target.write(b, off, len)
        for (i in off until off + len) accept(b[i].toInt())
    }

    private fun accept(byte: Int) {
        if (byte and 0xFF == '\n'.code) {
            flushLine()
            return
        }
        // Длинная строка режется только на границе символа UTF-8, не посреди кириллической буквы.
        if (buffer.size() >= limit && byte and 0xC0 != 0x80) flushLine()
        buffer.write(byte)
    }

    override fun flush() = target.flush()

    private fun flushLine() {
        val text = buffer.toString(Charsets.UTF_8).trimEnd('\r')
        buffer.reset()
        if (text.isNotBlank()) runCatching { line(text) }
    }
}
