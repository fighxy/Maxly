package app.maxly.data

import app.maxly.SharedFixtures
import app.maxly.SharedFixtures.Companion.array
import app.maxly.SharedFixtures.Companion.obj
import app.maxly.SharedFixtures.Companion.raw
import app.maxly.SharedFixtures.Companion.str
import com.maxly.core.api.MaxMessage
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Общие с iOS сценарии служебных сообщений из `test-fixtures/service-messages` (правила и
 * формат — в README каталога, Swift — `ServiceMessageFixtureTests`). Текст — путь приложения:
 * [ServiceMessages.text] поверх [com.maxly.core.media.controlFallbackText] ядра. Аккаунт —
 * `viewer`, имена — `names` сценария и `senderName` отправителя (их клиент берёт из стора).
 * Закрепление (`expect.kind` = `null`) — не событие чата; текст его строки тоже пишет ядро.
 */
class ServiceMessagesFixtureTest {
    private val fixtures = SharedFixtures(
        "service-messages",
        disagreements = mapOf(
            "events / pin-is-not-an-event" to
                "сценарий ждёт общую строку; ядро 2843f2d пишет «Закреплено: <текст>»",
            "events / unpin-is-not-an-event" to
                "сценарий ждёт общую строку; ядро 2843f2d пишет «Закрепление снято»",
        ),
    )

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures.files()
        assertEquals(listOf("events", "fallbacks"), files.map { it.nameWithoutExtension })
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        // events — 30 случаев, fallbacks — 18.
        assertEquals(48, fixtures.played)
        fixtures.finish("ServiceMessagesFixtureTest", files.size)
    }

    private fun play(file: String, fixture: JsonObject) {
        assertEquals("$file: kind", "control", fixture["kind"].str)
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["name"].str}") { check(case) }
        }
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
        val text = ServiceMessages.text(core, case["viewer"].str?.toLongOrNull()) { names[it]?.takeIf(String::isNotBlank) }
        check("служебное", true, ServiceMessages.isService(core))
        if (expect["kind"].str == null) {
            check("закрепление", true, MessageMapping.pinNotice(attaches) != null)
            // Сценарий без текста — старое правило «закрепление не событие, строка общая».
            check("текст", expect["text"].str ?: ServiceMessages.GENERIC, text)
            return
        }
        check("текст", expect["text"].str, text)
    }
}
