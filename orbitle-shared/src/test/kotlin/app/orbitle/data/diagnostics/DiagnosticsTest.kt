package app.orbitle.data.diagnostics

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class DiagnosticsTest {
    private val root: File = Files.createTempDirectory("orbitle-diag").toFile()
    private val savedHandler = Thread.getDefaultUncaughtExceptionHandler()

    @After
    fun tearDown() {
        Thread.setDefaultUncaughtExceptionHandler(savedHandler)
        AppLog.file = null
        root.deleteRecursively()
    }

    @Test
    fun logLinesReachTheDiskWithStackTraces() {
        val log = FileLog(File(root, "logs"), now = { 0L })
        log.append('I', "calls", "Звонок начат")
        log.append('E', "calls", "Не вышло", IllegalStateException("нет микрофона"))
        val text = log.read()
        assertTrue(text, text.contains(" I calls: Звонок начат\n"))
        assertTrue(text.contains(" E calls: Не вышло\njava.lang.IllegalStateException: нет микрофона"))
        assertTrue(text.contains("at app.orbitle.data.diagnostics.DiagnosticsTest"))
        assertFalse(log.isEmpty)
    }

    @Test
    fun logRotatesAndKeepsTheNewestLines() {
        val log = FileLog(File(root, "logs"), maxBytes = 200, files = 3)
        repeat(40) { log.append('I', "t", "строка номер $it") }
        val parts = log.parts().map { it.name }
        assertEquals(listOf("app.2.log", "app.1.log", "app.log"), parts)
        val text = log.read()
        assertTrue(text.contains("строка номер 39"))
        assertFalse(text.contains("строка номер 0\n"))
        // Строки идут по порядку: старые файлы раньше новых.
        assertTrue(text.indexOf("строка номер 37") < text.indexOf("строка номер 39"))
        log.clear()
        assertTrue(log.isEmpty)
        assertEquals("", log.read())
    }

    @Test
    fun tailStartsAtALineBoundary() {
        val log = FileLog(File(root, "logs"))
        repeat(50) { log.append('I', "t", "line $it") }
        val tail = log.tail(200)
        assertTrue(tail.length <= 200)
        assertTrue(tail.first().isDigit())
        assertTrue(tail.endsWith("line 49\n"))
    }

    @Test
    fun appLogWritesToFileAndEcho() {
        val log = FileLog(File(root, "logs"))
        val echoed = mutableListOf<String>()
        AppLog.file = log
        AppLog.echo = { level, tag, message, _ -> echoed += "$level/$tag/$message" }
        AppLog.w("calls", "ICE failed")
        assertEquals(listOf("W/calls/ICE failed"), echoed)
        assertTrue(log.read().contains("W calls: ICE failed"))
        AppLog.echo = { _, _, _, _ -> }
    }

    @Test
    fun reportsAreListedNewestFirstAndPruned() {
        var time = 1_000L
        val reports = CrashReports(File(root, "crashes"), keep = 3, now = { time })
        repeat(5) {
            time += 1_000
            reports.record(CrashReports.CRASH, "Сбой $it", "тело $it")
        }
        val list = reports.list()
        assertEquals(listOf("Сбой 4", "Сбой 3", "Сбой 2"), list.map { it.title })
        assertEquals(CrashReports.CRASH, list.first().kind)
        assertEquals(6_000L, list.first().timeMs)
        assertEquals("Сбой 4\nтело 4", reports.text(list.first().name))

        reports.remove(list.first().name)
        assertEquals(2, reports.list().size)
        reports.removeAll()
        assertTrue(reports.list().isEmpty())
    }

    @Test
    fun reportsWithTheSameTimeDoNotOverwriteEachOther() {
        val reports = CrashReports(File(root, "crashes"), now = { 5L })
        reports.record(CrashReports.NATIVE, "один", "")
        reports.record(CrashReports.NATIVE, "два", "")
        assertEquals(setOf("один", "два"), reports.list().map { it.title }.toSet())
        assertTrue(reports.list().all { it.kind == CrashReports.NATIVE })
    }

    @Test
    fun reportNamesCannotEscapeTheFolder() {
        val reports = CrashReports(File(root, "crashes"))
        File(root, "secret.txt").writeText("x")
        assertNull(reports.text("../secret.txt"))
        assertNull(reports.file("crash-1-x/../../secret.txt"))
        reports.remove("../secret.txt")
        assertTrue(File(root, "secret.txt").exists())
    }

    @Test
    fun errorReportHasTitleThreadInfoStackAndLog() {
        val reports = CrashReports(File(root, "crashes"), now = { 0L })
        val error = RuntimeException("обёртка", UnsatisfiedLinkError("no jingle"))
        val file = reports.recordError(CrashReports.CRASH, error, "main", "Orbitle 0.1.0\nAndroid 14", "12:00 I calls: старт\n")
        assertNotNull(file)
        val text = file!!.readText()
        val lines = text.lines()
        assertEquals("Сбой: java.lang.RuntimeException: обёртка ← java.lang.UnsatisfiedLinkError", lines[0])
        assertTrue(text.contains("Поток: main"))
        assertTrue(text.contains("Orbitle 0.1.0\nAndroid 14"))
        assertTrue(text.contains("Caused by: java.lang.UnsatisfiedLinkError: no jingle"))
        assertTrue(text.contains("Журнал перед сбоем:\n12:00 I calls: старт"))
    }

    @Test
    fun crashHandlerWritesAReportAndCallsThePreviousHandler() {
        val reports = CrashReports(File(root, "crashes"))
        val log = FileLog(File(root, "logs"))
        log.append('I', "calls", "последняя строка")
        var forwarded: Throwable? = null
        Thread.setDefaultUncaughtExceptionHandler { _, error -> forwarded = error }
        CrashHandler.install(reports, log) { "Orbitle test" }
        // Повторная установка не заворачивает обработчик сам в себя.
        val handler = Thread.getDefaultUncaughtExceptionHandler()
        CrashHandler.install(reports, log) { "Orbitle test" }
        assertSame(handler, Thread.getDefaultUncaughtExceptionHandler())

        val boom = IllegalStateException("Service.startForeground() not allowed")
        val thread = Thread({ throw boom }, "call-worker")
        thread.start()
        thread.join()

        assertSame(boom, forwarded)
        val report = reports.list().single()
        assertEquals(CrashReports.CRASH, report.kind)
        val text = reports.text(report.name)!!
        assertTrue(text, text.contains("Поток: call-worker"))
        assertTrue(text.contains("Orbitle test"))
        assertTrue(text.contains("последняя строка"))
        assertTrue(log.read().contains("E crash: Необработанное исключение в потоке call-worker"))
    }
}
