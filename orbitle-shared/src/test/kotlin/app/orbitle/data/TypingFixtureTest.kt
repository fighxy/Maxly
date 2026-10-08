package app.orbitle.data

import app.orbitle.domain.Chat
import app.orbitle.domain.ChatType
import app.orbitle.domain.Typist
import app.orbitle.domain.TypingKind
import app.orbitle.presentation.chat.ChatFormatter
import app.orbitle.presentation.chat.TypingSendPolicy
import app.orbitle.presentation.chatlist.ChatListFormatter
import com.max.core.state.MaxState
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.ZoneOffset

/**
 * Общие с iOS сценарии «печатает…» из `test-fixtures/typing` (описание — в README каталога):
 * тексты через [ChatListFormatter] и [ChatFormatter], сроки через [TypingTracker] над состоянием
 * ядра, отправка через [TypingSendPolicy]. Играются все файлы каталога.
 */
class TypingFixtureTest {
    private val now = 1_790_683_200_000L

    @Test
    fun everyFixtureIsPlayed() {
        val files = fixtures().listFiles { file -> file.extension == "json" }.orEmpty().sortedBy { it.name }
        assertTrue("нет сценариев в ${fixtures()}", files.isNotEmpty())
        for (file in files) {
            val fixture = Json.parseToJsonElement(file.readText()) as JsonObject
            assertEquals("${file.name}: name", file.nameWithoutExtension, fixture["name"].str)
            when (val kind = fixture["kind"].str) {
                "texts" -> texts(file.name, fixture)
                "expiry" -> expiry(file.name, fixture)
                "sending" -> sending(file.name, fixture)
                else -> error("${file.name}: незнакомый kind $kind")
            }
        }
    }

    private fun texts(file: String, fixture: JsonObject) {
        for (case in fixture["cases"] as JsonArray) {
            case as JsonObject
            val where = "$file / ${case["name"].str}"
            val type = when (case["chat"].str) {
                "private" -> ChatType.PRIVATE
                "group" -> ChatType.GROUP
                "channel" -> ChatType.CHANNEL
                else -> error("$where: chat ${case["chat"]}")
            }
            val typists = (case["typing"] as JsonArray).map {
                it as JsonObject
                Typist(it["name"].str, TypingKind.of(it["type"].str), it["startedAt"].long!!, it["userId"].str!!)
            }
            val chat = Chat(id = "10", title = "Чат", type = type, updatedAtMs = now)
            val item = ChatListFormatter(ZoneOffset.UTC).item(chat, now, typists)
            val list = item.preview.takeIf { item.previewStyle == app.orbitle.presentation.chatlist.ChatListItem.PreviewStyle.TYPING }
            assertEquals("$where: list", case["list"].str, list)
            // Шапка: тот же текст; в iOS точки рисует экран, у нас «…» остаётся в строке.
            val (subtitle, accent) = ChatFormatter(ZoneOffset.UTC).subtitle(ChatHeaderInfo(chat, typing = typists), now)
            assertEquals("$where: header", case["header"].str, subtitle.takeIf { accent }?.removeSuffix("…"))
        }
    }

    private fun expiry(file: String, fixture: JsonObject) {
        val ttl = fixture["ttlMs"].long!!
        val tracker = TypingTracker(ttl)
        val chats = linkedMapOf<String, Long>()
        fun chat(id: String) = chats.getOrPut(id) { chats.size + 1L }
        var typing = mapOf<Long, Map<Long, Long>>()
        var types = mapOf<Long, Map<Long, String>>()
        for ((index, step) in (fixture["steps"] as JsonArray).withIndex()) {
            step as JsonObject
            val at = step["at"].long!!
            val where = "$file, шаг $index (at $at)"
            (step["push"] as? JsonObject)?.let { push ->
                val c = chat(push["chatId"].str!!)
                val u = push["userId"].str!!.toLong()
                typing = typing + (c to (typing[c].orEmpty() + (u to at)))
                types = types + (c to (types[c].orEmpty() + (u to TypingKind.of(push["type"].str).raw)))
            }
            (step["message"] as? JsonObject)?.let { message ->
                val c = chat(message["chatId"].str!!)
                val u = message["userId"].str!!.toLong()
                typing[c]?.let { typing = typing + (c to (it - u)) }
            }
            // Как экран с тиком: трекер спрашивают на каждом шаге.
            val state = MaxState(me = 0, typing = typing, typingTypes = types)
            val actual = chats.mapNotNull { (name, id) ->
                val list = tracker.typists(state, id, at) { null }
                if (list.isEmpty()) null else name to list.map { it.userId to it.kind }
            }.toMap()
            (step["expect"] as? JsonObject)?.let { expect ->
                val wanted = expect.mapValues { (_, people) ->
                    (people as JsonArray).map { it as JsonObject; it["userId"].str!! to TypingKind.of(it["type"].str) }
                }
                assertEquals(where, wanted, actual)
            }
        }
    }

    private fun sending(file: String, fixture: JsonObject) {
        val policy = TypingSendPolicy()
        for ((index, step) in (fixture["steps"] as JsonArray).withIndex()) {
            step as JsonObject
            val at = step["at"].long!!
            val where = "$file, шаг $index (at $at, ${step["do"].str})"
            val chatId = step["chatId"].str
            val postId = step["postId"].str
            val canWrite = (step["canWrite"] as? JsonPrimitive)?.contentOrNull?.toBooleanStrict() ?: true
            val kind = TypingKind.of(step["type"].str)
            val sent = when (step["do"].str) {
                "editText" -> listOfNotNull(policy.editText(chatId!!, at, postId, canWrite))
                "startRecording" -> listOfNotNull(policy.startRecording(chatId!!, kind, at, postId, canWrite))
                "stopRecording" -> emptyList<TypingSendPolicy.Frame>().also { policy.stopRecording(chatId!!) }
                "uploadProgress" -> listOfNotNull(policy.uploadProgress(chatId!!, kind, at, postId, canWrite))
                "openStickers" -> listOfNotNull(policy.openStickers(chatId!!, at, postId, canWrite))
                "tick" -> policy.tick(at)
                else -> error("$where: незнакомый шаг")
            }
            val wanted = (step["sent"] as JsonArray).map {
                it as JsonObject
                TypingSendPolicy.Frame(it["chatId"].str!!, TypingKind.of(it["type"].str), it["postId"].str)
            }
            assertEquals(where, wanted, sent)
        }
    }

    private val JsonElement?.str: String? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull?.takeIf { it.isNotEmpty() }
    private val JsonElement?.long: Long? get() = (this as? JsonPrimitive)?.longOrNull

    private fun fixtures(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "test-fixtures/typing")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        error("нет каталога test-fixtures/typing выше ${File("").absolutePath}")
    }
}
