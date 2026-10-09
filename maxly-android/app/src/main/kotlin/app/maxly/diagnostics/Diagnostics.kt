package app.maxly.diagnostics

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import app.maxly.BuildConfig
import app.maxly.data.diagnostics.AppLog
import app.maxly.data.diagnostics.CrashHandler
import app.maxly.data.diagnostics.CrashReports
import app.maxly.data.diagnostics.FileLog
import kotlinx.coroutines.CoroutineExceptionHandler
import java.io.File
import java.util.Collections

/**
 * Журнал и отчёты о сбоях на Android. Включается первым делом в `MaxlyApp.onCreate`:
 * журнал пишется в `files/logs`, отчёты — в `files/crashes`; оба показывает экран
 * «О приложении». Нативные падения (WebRTC) и зависания Java-обработчик не видит — о них
 * рассказывает система на следующем запуске (`ApplicationExitInfo`, Android 11+).
 */
object Diagnostics {
    private const val TAG = "Maxly"
    private const val PREFS = "maxly.diagnostics"
    private const val KEY_EXIT_SEEN = "exitSeenMs"
    private const val EXIT_LOOKBACK_MS = 7L * 24 * 60 * 60 * 1000
    private const val TRACE_LIMIT = 64 * 1024

    @Volatile
    var log: FileLog? = null
        private set

    @Volatile
    var reports: CrashReports? = null
        private set

    private var appContext: Context? = null
    private val reported = Collections.synchronizedSet(HashSet<String>())

    fun init(context: Context) {
        val app = context.applicationContext
        appContext = app
        val log = FileLog(File(app.filesDir, "logs"))
        val reports = CrashReports(File(app.filesDir, "crashes"))
        this.log = log
        this.reports = reports
        AppLog.echo = { level, tag, message, error ->
            val priority = when (level) {
                'E' -> Log.ERROR
                'W' -> Log.WARN
                else -> Log.INFO
            }
            val text = if (error == null) message else message + "\n" + Log.getStackTraceString(error)
            Log.println(priority, "$TAG/$tag", text)
        }
        AppLog.file = log
        CrashHandler.install(reports, log) { info() }
        // Сначала — что случилось в прошлый раз: хвост журнала ещё от того запуска.
        try {
            recordExitReasons(app, reports, log)
        } catch (e: Exception) {
            AppLog.w("app", "Не прочитал причины прошлого завершения", e)
        }
        AppLog.i("app", "Запуск. " + info().replace('\n', ' '))
    }

    /** Версия, сборка и устройство — в начало отчёта и в строку запуска. */
    fun info(): String = buildString {
        append("Maxly ").append(BuildConfig.VERSION_NAME).append(" (").append(BuildConfig.VERSION_CODE).append("), сборка ")
            .append(BuildConfig.BUILD_SHA).append(", ядро ").append(BuildConfig.CORE_REVISION)
        if (BuildConfig.DEBUG) append(", debug")
        append('\n')
        append("Android ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append("), ")
            .append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append(", ").append(Build.SUPPORTED_ABIS.joinToString())
    }

    /**
     * Обработчик корутин приложения: исключение, которое раньше роняло процесс, пишется в журнал
     * и в отчёт (один отчёт на одно место за запуск), а приложение живёт дальше.
     */
    val coroutineHandler = CoroutineExceptionHandler { context, error ->
        nonFatal("корутина ${context[kotlinx.coroutines.CoroutineName]?.name.orEmpty()}".trim(), error)
    }

    fun nonFatal(where: String, error: Throwable) {
        AppLog.e("app", "Необработанная ошибка ($where)", error)
        val signature = error.javaClass.name + "@" + error.stackTrace.firstOrNull()
        if (!reported.add(signature)) return
        reports?.recordError(CrashReports.ERROR, error, Thread.currentThread().name, info(), log?.tail().orEmpty())
    }

    // region Причины прошлых завершений

    private fun recordExitReasons(context: Context, reports: CrashReports, log: FileLog) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val seen = prefs.getLong(KEY_EXIT_SEEN, now - EXIT_LOOKBACK_MS)
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = manager.getHistoricalProcessExitReasons(context.packageName, 0, 16)
        var newest = seen
        val tail = log.tail()
        for (exit in exits.sortedBy { it.timestamp }) {
            if (exit.timestamp <= seen) continue
            newest = maxOf(newest, exit.timestamp)
            val kind = when (exit.reason) {
                ApplicationExitInfo.REASON_CRASH_NATIVE -> CrashReports.NATIVE
                ApplicationExitInfo.REASON_ANR -> CrashReports.ANR
                else -> null
            }
            val line = "Прошлое завершение: ${reasonName(exit.reason)}, ${exit.description.orEmpty()}, процесс ${exit.processName}"
            if (kind == null) {
                if (exit.reason == ApplicationExitInfo.REASON_CRASH) AppLog.i("app", line)
                continue
            }
            AppLog.w("app", line)
            val details = buildString {
                append("Причина: ").append(reasonName(exit.reason)).append('\n')
                exit.description?.takeIf { it.isNotBlank() }?.let { append("Описание: ").append(it).append('\n') }
                append("Процесс: ").append(exit.processName).append(", важность ").append(exit.importance)
                    .append(", PSS ").append(exit.pss).append(" КБ, RSS ").append(exit.rss).append(" КБ\n")
                trace(exit, kind)?.let { append('\n').append(it) }
            }
            val title = CrashReports.kindTitle(kind) + (exit.description?.takeIf { it.isNotBlank() }?.let { ": $it" } ?: "")
            reports.record(kind, title, CrashReports.body(kind, exit.timestamp, null, info(), details, tail), exit.timestamp)
        }
        prefs.edit().putLong(KEY_EXIT_SEEN, maxOf(newest, now)).apply()
    }

    /**
     * След из системы: у зависания — текстовые стеки потоков, у нативного падения — tombstone
     * в protobuf, из него берутся читаемые строки (сообщение abort, имена функций).
     */
    private fun trace(exit: ApplicationExitInfo, kind: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val bytes = try {
            exit.traceInputStream?.use { input ->
                val buffer = ByteArray(TRACE_LIMIT * 4)
                var total = 0
                while (total < buffer.size) {
                    val read = input.read(buffer, total, buffer.size - total)
                    if (read <= 0) break
                    total += read
                }
                buffer.copyOf(total)
            }
        } catch (_: Exception) {
            null
        } ?: return null
        if (kind == CrashReports.ANR) return "Стеки потоков:\n" + String(bytes).take(TRACE_LIMIT)
        val strings = printableRuns(bytes).joinToString("\n").take(TRACE_LIMIT)
        return if (strings.isEmpty()) null else "Строки из tombstone:\n$strings"
    }

    private fun printableRuns(bytes: ByteArray, min: Int = 6): List<String> {
        val runs = ArrayList<String>()
        val current = StringBuilder()
        for (byte in bytes) {
            val char = byte.toInt() and 0xFF
            if (char in 0x20..0x7E) {
                current.append(char.toChar())
            } else {
                if (current.length >= min) runs += current.toString()
                current.setLength(0)
            }
        }
        if (current.length >= min) runs += current.toString()
        return runs
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_CRASH -> "сбой Java"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "сбой нативного кода"
        ApplicationExitInfo.REASON_ANR -> "зависание (ANR)"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "нехватка памяти"
        ApplicationExitInfo.REASON_EXIT_SELF -> "выход"
        ApplicationExitInfo.REASON_SIGNALED -> "сигнал"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "остановлено пользователем"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "перерасход ресурсов"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "сбой запуска"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "изменились разрешения"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "умерла зависимость"
        ApplicationExitInfo.REASON_OTHER -> "другое"
        else -> "код $reason"
    }

    // endregion

    // region Отправка

    /** Журнал файлом через системный лист «Поделиться». */
    fun shareLog(context: Context): Boolean {
        val text = log?.read().orEmpty()
        if (text.isBlank()) return false
        val header = "Журнал Maxly\n" + info() + "\n\n"
        return share(context, "maxly-log.txt", header + text, "Журнал Maxly")
    }

    fun shareReport(context: Context, name: String): Boolean {
        val text = reports?.text(name) ?: return false
        return share(context, name, text, "Отчёт о сбое Maxly")
    }

    private fun share(context: Context, fileName: String, text: String, subject: String): Boolean = try {
        val dir = File(context.cacheDir, "diagnostics").apply { mkdirs() }
        val file = File(dir, fileName)
        file.writeText(text)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_SUBJECT, subject)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, subject).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        AppLog.w("app", "Не удалось поделиться $fileName", e)
        false
    }

    // endregion
}
