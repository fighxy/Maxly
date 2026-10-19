package app.maxly.data

import app.maxly.SharedFixtures
import app.maxly.SharedFixtures.Companion.array
import app.maxly.SharedFixtures.Companion.obj
import app.maxly.SharedFixtures.Companion.raw
import app.maxly.SharedFixtures.Companion.str
import com.maxly.core.api.MaxMessage
import com.maxly.core.media.controlFallbackText
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Общие с iOS сценарии служебных сообщений из `test-fixtures/service-messages` (правила и
 * формат — в README каталога, Swift — `ServiceMessageFixtureTests`). Текст — путь приложения:
 * [ServiceMessages.text] поверх [com.maxly.core.media.controlFallbackText] ядра. Аккаунт —
 * `viewer`, имена — `names` сценария и `senderName` отправителя (их клиент берёт из стора).
 * Закрепление (`expect.kind` = `null`) — не событие чата; текст его строки тоже пишет ядро.
 */
class ServiceMessagesFixtureTest {
    private val fixtures = SharedFixtures("service-messages")

    @Test
    fun everyFixtureIsPlayed() {
        // Играются все файлы каталога и все их случаи: новый случай или файл счётчика не требует.
        val files = fixtures.files()
        var expected = 0
        for (file in files) expected += play(file.nameWithoutExtension, fixtures.read(file))
        assertTrue("нет случаев", expected > 0)
        assertEquals("сыграны не все случаи", expected, fixtures.played)
        fixtures.finish("ServiceMessagesFixtureTest", files.size)
    }

    /** Играет все случаи файла; возвращает их число. Имена случаев в файле не повторяются. */
    private fun play(file: String, fixture: JsonObject): Int {
        assertEquals("$file: kind", "control", fixture["kind"].str)
        val cases = fixtures.cases(fixture)
        val names = cases.map { it["name"].str }
        assertTrue("$file: случай без имени", names.none { it.isNullOrBlank() })
        assertEquals("$file: имена случаев повторяются", names.size, names.toSet().size)
        for (case in cases) {
            fixtures.case("$file / ${case["name"].str}") { check(case) }
        }
        return cases.size
    }

    private fun SharedFixtures.Case.check(case: JsonObject) {
        val message = case["message"].obj ?: error("$where: нет message")
        val attaches = message["attaches"].array.map { it.raw() }
        val expect = case["expect"].obj ?: error("$where: нет expect")
        val sender = message["sender"].str?.toLongOrNull()
        val core = MaxMessage.from(
            mapOf("id" to 1L, "chatId" to 9L, "sender" to sender, "text" to message["text"].str.orEmpty(), "time" to 1L, "type" to "USER", "attaches" to attaches),
            9L,
        )!!
        val names = case["names"].obj.orEmpty().mapNotNull { (id, name) -> id.toLongOrNull()?.let { it to name.str } }.toMap() +
            listOfNotNull(sender?.let { it to message["senderName"].str })
        val viewer = case["viewer"].str?.toLongOrNull()
        val nameOf = { id: Long -> names[id]?.takeIf(String::isNotBlank) }
        val text = ServiceMessages.text(core, viewer, nameOf = nameOf)
        check("служебное", true, ServiceMessages.isService(core))
        // coreText сценария — то, что пишет само ядро.
        case["coreText"].str?.let { coreText ->
            check("текст ядра", coreText, controlFallbackText(ServiceMessages.control(core)!!, selfId = viewer, actorId = sender, nameOf = nameOf))
        }
        if (expect["kind"].str == null) {
            // Закрепление: не событие чата, но текст плашки тоже пишет ядро; он обязан быть в сценарии.
            check("закрепление", true, MessageMapping.pinNotice(attaches) != null)
            check("текст плашки в сценарии", true, expect["text"].str != null)
        }
        check("текст", expect["text"].str, text)
    }
}
