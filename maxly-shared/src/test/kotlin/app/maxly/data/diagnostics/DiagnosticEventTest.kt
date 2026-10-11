package app.maxly.data.diagnostics

import java.nio.file.Files
import java.util.concurrent.Executors
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class DiagnosticEventTest {
    @Test fun concurrentEventsRemainValidOrderedAndPrivate() {
        val dir = Files.createTempDirectory("diagnostic-events").toFile()
        val log = FileLog(dir, maxBytes = 1_000_000)
        AppLog.file = log
        val pool = Executors.newFixedThreadPool(4)
        try {
            val tasks = (0 until 4).map { worker -> pool.submit {
                repeat(30) { DiagnosticEvent.event("test.event", mapOf("worker" to worker.toString(), "text" to "PRIVATE", "token" to "SECRET", "chat" to DiagnosticEvent.id("12345"))) }
            } }
            tasks.forEach { it.get() }
            DiagnosticEvent.event("chat.viewport", mapOf("visible" to "0"), snapshot = true)
            val marker = DiagnosticEvent.problemNow()
            val rows = log.read().lineSequence().filter { it.startsWith("{") }.map { Json.parseToJsonElement(it).jsonObject }.toList()
            assertTrue(rows.size >= 123)
            val seqs = rows.map { it.getValue("seq").jsonPrimitive.long }
            assertEquals(seqs.sorted().distinct(), seqs)
            assertTrue(rows.all { it.getValue("schema").jsonPrimitive.int == 1 })
            assertEquals("problem.snapshot", rows.last().getValue("event").jsonPrimitive.content)
            assertEquals(marker, rows.last().getValue("fields").jsonObject.getValue("marker").jsonPrimitive.content)
            assertFalse(log.read().contains("PRIVATE"))
            assertFalse(log.read().contains("SECRET"))
            assertFalse(log.read().contains("12345"))
            log.clear()
            assertEquals("", log.read())
            DiagnosticEvent.event("after.clear")
            assertEquals(1, log.read().lineSequence().filter { it.isNotBlank() }.count())
        } finally { pool.shutdownNow(); AppLog.file = null; log.close(); dir.deleteRecursively() }
    }

    @Test fun cancellationRecordsTerminalEventAndRethrows() = runBlocking {
        val dir = Files.createTempDirectory("diagnostic-cancel").toFile()
        val log = FileLog(dir)
        AppLog.file = log
        try {
            try {
                DiagnosticEvent.operation("history.older") { throw java.util.concurrent.CancellationException() }
                fail("Cancellation must propagate")
            } catch (_: java.util.concurrent.CancellationException) { }
            val rows = log.read().lineSequence().filter { it.startsWith("{") }.map { Json.parseToJsonElement(it).jsonObject }.toList()
            assertEquals(2, rows.size)
            assertEquals("cancelled", rows.last().getValue("fields").jsonObject.getValue("result").jsonPrimitive.content)
            assertEquals(rows.first().getValue("fields").jsonObject["operation"], rows.last().getValue("fields").jsonObject["operation"])
        } finally { AppLog.file = null; log.close(); dir.deleteRecursively() }
    }
}
