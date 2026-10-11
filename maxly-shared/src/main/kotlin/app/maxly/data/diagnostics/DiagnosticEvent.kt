package app.maxly.data.diagnostics

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

/** Local-only, versioned events. Fields contain measurements/enums, never user content. */
object DiagnosticEvent {
    private val session = UUID.randomUUID().toString()
    private val started = System.nanoTime()
    private var sequence = 0L
    private var detailedUntil = 0L
    private val snapshots = LinkedHashMap<String, Map<String, String>>()

    fun id(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest((session + value).toByteArray()).take(8).joinToString("") { "%02x".format(it) }

    @Synchronized fun event(name: String, fields: Map<String, String> = emptyMap(), snapshot: Boolean = false) {
        val safe = fields.entries.take(40).associate { (key, value) ->
            key.take(64) to if (Regex("(?i).*(token|password|text|caption|url|payload|phone|secret).*").matches(key)) "[redacted]" else value.take(256)
        }
        if (snapshot) {
            snapshots[name] = safe + ("observed_uptime_ms" to ((System.nanoTime() - started) / 1_000_000).toString())
            if (snapshots.size > 16) snapshots.remove(snapshots.keys.first())
        }
        val line = JsonObject(mapOf(
            "schema" to JsonPrimitive(1), "time" to JsonPrimitive(Instant.now().toString()),
            "uptime_ms" to JsonPrimitive((System.nanoTime() - started) / 1_000_000),
            "session" to JsonPrimitive(session), "seq" to JsonPrimitive(++sequence),
            "event" to JsonPrimitive(name.take(96)),
            "fields" to JsonObject(safe.mapValues { JsonPrimitive(it.value) }),
        )).toString()
        AppLog.file?.append('I', "diagnostic", line)
    }

    @Synchronized fun problemNow(): String {
        val marker = UUID.randomUUID().toString().take(8)
        event("problem.mark", mapOf("marker" to marker))
        snapshots.toMap().forEach { (name, fields) -> event("problem.snapshot", fields + mapOf("source" to name, "marker" to marker)) }
        return marker
    }

    @Synchronized fun enableDetailed() {
        detailedUntil = System.nanoTime() + 15L * 60 * 1_000_000_000
        event("diagnostics.detail", mapOf("duration_seconds" to "900"))
    }
    @Synchronized fun sampleIntervalMs(): Long = if (System.nanoTime() < detailedUntil) 250 else 1000

    suspend fun <T> operation(name: String, fields: Map<String, String> = emptyMap(), body: suspend () -> T): T {
        val operation = UUID.randomUUID().toString().take(8)
        val start = System.nanoTime()
        val context = fields + ("operation" to operation)
        event("$name.start", context)
        try {
            return body().also { event("$name.finish", context + mapOf("result" to "ok", "duration_ms" to ((System.nanoTime() - start) / 1_000_000).toString())) }
        } catch (error: Exception) {
            event("$name.finish", context + mapOf("result" to if (error is java.util.concurrent.CancellationException) "cancelled" else "error", "error_type" to error.javaClass.simpleName, "duration_ms" to ((System.nanoTime() - start) / 1_000_000).toString()))
            throw error
        }
    }
}

/** Emits only crossed quarter milestones, never one event per byte chunk. */
class DiagnosticProgress(private val fields: Map<String, String>) {
    private val last = java.util.concurrent.atomic.AtomicInteger(-1)
    fun report(fraction: Float) {
        if (!fraction.isFinite()) return
        val bucket = (fraction.coerceIn(0f, 1f) * 4).toInt()
        while (true) {
            val previous = last.get()
            if (bucket <= previous) return
            if (last.compareAndSet(previous, bucket)) {
                DiagnosticEvent.event("media.upload.progress", fields + ("percent" to (bucket * 25).toString()))
                return
            }
        }
    }
}
