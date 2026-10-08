package app.orbitle

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.io.File

/**
 * Общие с iOS сценарии из `test-fixtures/<каталог>`: чтение файлов и учёт случаев. Каждый
 * проигрыватель гоняет все файлы своего каталога; незнакомый `kind` — ошибка.
 *
 * [disagreements] — случаи (`файл / случай`), в которых ядро или сценарий расходятся с правилом,
 * с причиной. Такой случай всё равно играется и обязан расходиться: если он сошёлся, тест падает,
 * чтобы запись убрали. Пропусков нет.
 */
class SharedFixtures(private val dir: String, private val disagreements: Map<String, String> = emptyMap()) {
    var played = 0
        private set
    private val disagreed = mutableListOf<String>()
    private val seen = mutableSetOf<String>()

    /** Все `*.json` каталога по имени; каталога нет — ошибка (сценарии кладутся рядом с кодом). */
    fun files(): List<File> {
        val files = root().listFiles { file -> file.extension == "json" }.orEmpty().sortedBy { it.name }
        assertTrue("нет сценариев в ${root()}", files.isNotEmpty())
        return files
    }

    /** Файл сценариев: `name` совпадает с именем файла, `cases` не пуст. */
    fun read(file: File): JsonObject {
        val fixture = parse(file.readText())
        assertEquals("${file.name}: name", file.nameWithoutExtension, fixture["name"].str)
        assertTrue("${file.name}: нет случаев", (fixture["cases"] as? JsonArray).orEmpty().isNotEmpty())
        return fixture
    }

    fun cases(fixture: JsonObject): List<JsonObject> = (fixture["cases"] as JsonArray).map { it as JsonObject }

    /**
     * Один случай [where] (`файл / случай`): [body] сравнивает ожидаемое с полученным через
     * [Case.check]. Случай из [disagreements] обязан разойтись хоть в одной проверке.
     */
    fun case(where: String, body: Case.() -> Unit) {
        played++
        seen += where
        val run = Case(where).apply(body)
        val reason = disagreements[where]
        if (reason == null) {
            run.mismatches.firstOrNull()?.let { throw AssertionError(it) }
            assertTrue("$where: ни одной проверки", run.checks > 0)
        } else {
            assertTrue("$where сошёлся — убрать из расхождений ($reason)", run.mismatches.isNotEmpty())
            disagreed += "$where — $reason: ${run.mismatches.joinToString("; ")}"
        }
    }

    /** Итог: все записи расхождений нашлись среди сыгранных случаев. */
    fun finish(name: String, files: Int) {
        val unknown = disagreements.keys - seen
        assertTrue("расхождения без случая: $unknown", unknown.isEmpty())
        println("$name: $files файлов, $played случаев, расходятся ${disagreed.size}")
        disagreed.forEach { println("  РАСХОДИТСЯ $it") }
    }

    class Case(val where: String) {
        val mismatches = mutableListOf<String>()
        var checks = 0
            private set

        fun check(what: String, expected: Any?, actual: Any?) {
            checks++
            if (expected != actual) mismatches += "$where: $what — ждали <$expected>, получили <$actual>"
        }
    }

    private fun root(): File {
        var at: File? = File("").absoluteFile
        while (at != null) {
            val candidate = File(at, "test-fixtures/$dir")
            if (candidate.isDirectory) return candidate
            at = at.parentFile
        }
        error("нет каталога test-fixtures/$dir выше ${File("").absolutePath}")
    }

    companion object {
        fun parse(text: String): JsonObject = Json.parseToJsonElement(text) as JsonObject

        /** Значение JSON как его отдаёт сокет ядру: числа — `Long` (или `Double`), объекты — карты. */
        fun JsonElement.raw(): Any? = when (this) {
            is JsonNull -> null
            is JsonPrimitive -> if (isString) content else longOrNull ?: booleanOrNull ?: doubleOrNull
            is JsonObject -> LinkedHashMap<String, Any?>().also { out -> forEach { (k, v) -> out[k] = v.raw() } }
            is JsonArray -> map { it.raw() }
        }

        val JsonElement?.str: String? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
        val JsonElement?.long: Long? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.let { it.longOrNull ?: it.contentOrNull?.toLongOrNull() }
        val JsonElement?.bool: Boolean? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.booleanOrNull
        val JsonElement?.array: List<JsonElement> get() = (this as? JsonArray).orEmpty()
        val JsonElement?.obj: JsonObject? get() = this as? JsonObject
    }
}
