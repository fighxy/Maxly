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
 * формат — в README каталога, Swift — `ServiceMessageFixtureTests`). Вложения разбирает
 * [ServiceMessages.notice], текст строит [ServiceMessages.text]; `coreText` сценария — текст ядра
 * ([com.maxly.core.media.controlFallbackText]), как его подставляет iOS.
 */
class ServiceMessagesFixtureTest {
    private val fixtures = SharedFixtures("service-messages")

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
        val kind = expect["kind"].str
        val notice = ServiceMessages.notice(attaches)
        val sender = message["sender"].str.orEmpty()
        val messageText = message["text"].str.orEmpty()
        // Через сообщение ядра: строка служебная при любом исходе (закрепление — тоже).
        val core = MaxMessage.from(
            mapOf("id" to 1L, "chatId" to 9L, "sender" to sender.toLongOrNull(), "text" to messageText, "time" to 1L, "type" to "USER", "attaches" to attaches),
            9L,
        )!!
        check("служебное", true, ServiceMessages.isService(core))
        if (kind == null) {
            check("не событие", null, notice)
            check("закрепление", true, MessageMapping.pinNotice(attaches) != null)
            return
        }
        notice ?: run { check("событие разобрано", kind, null); return }
        check("kind", kind, ServiceMessages.kind(notice).fixtureName)
        val names = case["names"].obj.orEmpty().mapValues { it.value.str }
        val text = ServiceMessages.text(
            notice,
            actorId = sender,
            actorName = message["senderName"].str,
            viewerId = case["viewer"].str,
            names = { names[it] },
            messageText = messageText,
            coreText = case["coreText"].str,
        )
        check("текст", expect["text"].str, text)
        assertTrue(text.isNotBlank())
        // Путь приложения: текст ядра считает само ядро. Где сценарий задаёт coreText, ядро
        // обязано дать его же; где ядру сказать нечего, итог тот же, что у iOS.
        val fallback = controlFallbackText(ServiceMessages.control(core)!!)
        val coreText = case["coreText"].str
        if (coreText != null) check("текст ядра", coreText, fallback)
        if (coreText != null || fallback == null) {
            check("текст приложения", expect["text"].str, ServiceMessages.text(core, case["viewer"].str, { names[it] }, message["senderName"].str))
        }
    }
}
