package app.maxly.presentation.chat

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * Общие с iOS константы из `test-fixtures/client-rules/constants.json` (смысл — в README
 * каталога): [ReadMarkRules] должны совпадать с файлом.
 */
class ClientRulesFixtureTest {

    @Test
    fun readMarkRulesMatchTheSharedFile() {
        val file = File(fixtures(), "constants.json")
        val root = Json.parseToJsonElement(file.readText()).jsonObject
        assertEquals("name", "constants", (root["name"] as JsonPrimitive).content)
        assertEquals("version", 1, (root["version"] as JsonPrimitive).intOrNull)
        val marks = root["readMarks"] as JsonObject
        // Новое поле без проверки здесь — ошибка: его не с чем сверить.
        assertEquals(setOf("debounceMs", "minVisibleFraction"), marks.keys)
        assertEquals(ReadMarkRules.DEBOUNCE_MS, (marks["debounceMs"] as JsonPrimitive).longOrNull)
        val fraction = (marks["minVisibleFraction"] as JsonPrimitive).doubleOrNull ?: error("нет minVisibleFraction")
        assertEquals(ReadMarkRules.MIN_VISIBLE_FRACTION.toDouble(), fraction, 1e-6)
    }

    private fun fixtures(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "test-fixtures/client-rules")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        error("нет каталога test-fixtures/client-rules выше ${File("").absolutePath}")
    }
}
