package app.maxly.presentation.chat

import app.maxly.SharedFixtures
import app.maxly.SharedFixtures.Companion.array
import app.maxly.SharedFixtures.Companion.bool
import app.maxly.SharedFixtures.Companion.long
import app.maxly.SharedFixtures.Companion.obj
import app.maxly.SharedFixtures.Companion.str
import app.maxly.data.DeleteStore
import app.maxly.data.MessageMapping
import app.maxly.domain.Message
import app.maxly.domain.MessageContent
import app.maxly.domain.MessageStatus
import com.maxly.core.api.MaxMessage
import com.maxly.core.state.MaxState
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

/**
 * Общие с iOS сценарии выбора сообщений из `test-fixtures/selection` (правила — в README
 * каталога): удаление — план ядра через [app.maxly.data.DeletePlans] над стором ядра с чатом,
 * правами и сообщениями сценария ([DeleteStore]; его же спрашивают меню, шапка выбора и диалог
 * через [ChatViewModel]), пересылка — шаги [MessageSelection.forwardPlan], по которым
 * идёт `ChatViewModel.forwardSelection`, копирование — [MessageSelection.copyText] над
 * сообщениями из [MessageMapping.message].
 */
class SelectionFixtureTest {
    private val fixtures = SharedFixtures("selection")

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures.files()
        for (file in files) play(file.nameWithoutExtension, fixtures.read(file))
        assertTrue("сыграно ${fixtures.played} случаев", fixtures.played >= files.size)
        fixtures.finish("SelectionFixtureTest", files.size)
    }

    private fun play(file: String, fixture: JsonObject) {
        val kind = fixture["kind"].str
        for (case in fixtures.cases(fixture)) {
            fixtures.case("$file / ${case["name"].str}") {
                when (kind) {
                    "delete" -> delete(case)
                    "forward" -> forward(case)
                    "copy" -> copy(case)
                    else -> error("$file: незнакомый kind $kind")
                }
            }
        }
    }

    // ---- kind: delete ----------------------------------------------------------------------------

    private fun SharedFixtures.Case.delete(case: JsonObject) {
        val chat = case["chat"].obj!!
        val chatId = chat["id"].str!!
        val type = when (val t = chat["type"].str) {
            "DIALOG", "CHAT", "CHANNEL" -> t
            else -> error("незнакомый type $t")
        }
        val messages = case["messages"].array.map {
            it as JsonObject
            val status = when (val s = it["state"].str) {
                "sent" -> MessageStatus.SENT
                "sending" -> MessageStatus.SENDING
                "failed" -> MessageStatus.FAILED
                else -> error("незнакомое state $s")
            }
            Message(id = it["id"].str!!, chatId = chatId, authorId = it["author"].str!!, text = "т", timeMs = it["time"].long!!, status = status)
        }
        val plan = DeleteStore.plan(
            me = case["me"].str,
            chatId = chatId,
            type = type,
            admin = chat["admin"].bool == true,
            messages = messages,
            // Как MaxClient.editTimeoutSeconds: нет edit-timeout — 0.
            editTimeoutSeconds = case["editTimeout"].long ?: 0L,
            nowMs = case["now"].long!!,
        )
        val expect = case["expect"].obj!!
        check("scopes", expect["scopes"].obj!!.mapValues { it.value.str }, plan.scopes.mapValues { it.value.name.lowercase() })
        check("canDelete", expect["canDelete"].bool, plan.canDelete)
        check("showsForEveryone", expect["showsForEveryone"].bool, plan.showsForEveryone)
        check("forEveryoneByDefault", expect["forEveryoneByDefault"].bool, plan.forEveryoneByDefault)
        check("forcesForEveryone", expect["forcesForEveryone"].bool, plan.forcesForEveryone)
    }

    // ---- kind: forward ---------------------------------------------------------------------------

    private fun SharedFixtures.Case.forward(case: JsonObject) {
        val messages = case["messages"].array.map {
            it as JsonObject
            Message(id = it["id"].str!!, chatId = "5", authorId = "1", text = "т", timeMs = it["time"].long!!)
        }
        val steps = MessageSelection.forwardPlan(messages, case["targets"].array.map { it.str!! }, case["comment"].str)
        val expected = case["expect"].obj!!["requests"].array.map {
            it as JsonObject
            it["comment"].str?.let { text -> "${it["target"].str} комментарий «$text»" } ?: "${it["target"].str} ← ${it["messageId"].str}"
        }
        val actual = steps.map {
            when (it) {
                is MessageSelection.ForwardStep.Comment -> "${it.target} комментарий «${it.text}»"
                is MessageSelection.ForwardStep.Forward -> "${it.target} ← ${it.messageId}"
            }
        }
        check("requests", expected, actual)
    }

    // ---- kind: copy ------------------------------------------------------------------------------

    private fun SharedFixtures.Case.copy(case: JsonObject) {
        val zone = ZoneId.of(case["timeZone"].str!!)
        val messages = case["messages"].array.map {
            it as JsonObject
            val raw = linkedMapOf<String, Any?>("id" to it["id"].long, "chatId" to 5L, "time" to it["time"].long, "type" to "USER", "sender" to 2L, "text" to it["text"].str)
            it["media"].str?.let { media -> raw["attaches"] = listOf(attach(media)) }
            val message = MessageMapping.message(MaxMessage.from(raw, 5L)!!, 5L, MaxState(me = 1L))
            check("вложение ${it["media"].str}", it["media"].str != null, message.content != MessageContent.empty && message.content.attachments.isNotEmpty())
            // Имя автора — из сценария (у приложения — authorLabel чата).
            message.copy(authorName = it["authorName"].str.orEmpty())
        }
        check("буфер", case["expect"].str, MessageSelection.copyText(messages, zone))
    }

    /** Вложение сервера для подписи `media` сценария. */
    private fun attach(media: String): Map<String, Any?> = when (media) {
        "PHOTO" -> mapOf("_type" to "PHOTO", "photoId" to 1L, "baseUrl" to "https://example.org/p")
        "VIDEO" -> mapOf("_type" to "VIDEO", "videoId" to 2L)
        "VIDEO_MESSAGE" -> mapOf("_type" to "VIDEO", "videoId" to 3L, "videoType" to 1L)
        "VOICE" -> mapOf("_type" to "AUDIO", "audioId" to 4L)
        "FILE" -> mapOf("_type" to "FILE", "fileId" to 5L, "name" to "отчёт.pdf")
        "STICKER" -> mapOf("_type" to "STICKER", "stickerId" to 6L)
        "CONTACT" -> mapOf("_type" to "CONTACT", "contactId" to 7L, "name" to "Иван")
        "POLL" -> mapOf(
            "_type" to "POLL", "pollId" to 8L, "title" to "Куда?",
            "answers" to listOf(mapOf("answerId" to 1L, "text" to "Туда"), mapOf("answerId" to 2L, "text" to "Сюда")),
        )
        else -> error("незнакомое media $media")
    }
}
