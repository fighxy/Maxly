package app.maxly.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.PrintStream

/** Вывод консоли в журнал построчно и стеки потоков для отчёта о зависании. */
class DiagnosticsTextTest {
    @Test
    fun consoleGoesToLogLineByLine() {
        val console = ByteArrayOutputStream()
        val lines = mutableListOf<String>()
        val out = PrintStream(LineTee(console, limit = 16) { lines += it }, true, Charsets.UTF_8)
        out.print("первая ")
        out.println("строка")
        out.print("windows\r\n")
        out.println()
        out.print("x".repeat(20))
        out.flush()
        assertEquals("первая строка\nwindows\r\n\n" + "x".repeat(20), console.toString(Charsets.UTF_8).replace(System.lineSeparator(), "\n"))
        // Пустые строки не пишутся, слишком длинная режется по пределу между буквами, а не посреди буквы.
        assertEquals(listOf("первая ст", "рока", "windows", "x".repeat(16)), lines)
    }

    @Test
    fun threadDumpHasEveryThreadWithFullStacks() {
        val lock = Object()
        val started = java.util.concurrent.CountDownLatch(1)
        val holder = Thread({
            synchronized(lock) {
                started.countDown()
                Thread.sleep(5_000)
            }
        }, "test-holder").apply { isDaemon = true; start() }
        started.await()
        val waiter = Thread({ synchronized(lock) { } }, "test-waiter").apply { isDaemon = true; start() }
        while (waiter.state != Thread.State.BLOCKED) Thread.sleep(10)
        val dump = ThreadDump.capture()
        assertTrue(dump, "\"test-holder\"" in dump)
        assertTrue(dump, "\"test-waiter\"" in dump)
        // Видно, кто держит монитор, которого ждёт поток.
        assertTrue(dump, "owned by \"test-holder\"" in dump)
        assertTrue(dump, "- locked" in dump)
        holder.interrupt()
    }
}
