package app.orbitle.data.calls

import app.orbitle.domain.CallConnection
import app.orbitle.domain.CallPhase
import app.orbitle.domain.CallRole
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * Общие с iOS сценарии ws2 из `test-fixtures/calls/ws2`: тот же обмен кадрами, что проверяют
 * для Swift-реализации. Формат файлов — в README рядом с ними.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class Ws2FixtureTest {
    private val timing = CallSession.Timing(wake = 60_000, gathering = 20, reconnect = listOf(5, 5), levels = 60_000)

    @Test fun outgoingDirect() = play("outgoing-direct")

    @Test fun outgoingCanceled() = play("outgoing-canceled")

    @Test fun outgoingDeclined() = play("outgoing-declined")

    @Test fun incomingAnswered() = play("incoming-answered")

    @Test fun incomingRejected() = play("incoming-rejected")

    @Test fun incomingMissed() = play("incoming-missed")

    @Test fun ice() = play("ice")

    @Test fun errors() = play("errors")

    @Test fun conversationClosed() = play("conversation-closed")

    /** Новый файл без теста здесь — ошибка: сценарий должен проигрываться. */
    @Test
    fun everyFixtureIsPlayed() {
        val played = setOf(
            "outgoing-direct", "outgoing-canceled", "outgoing-declined", "incoming-answered", "incoming-rejected",
            "incoming-missed", "ice", "errors", "conversation-closed",
        )
        val files = fixtures().listFiles { file -> file.extension == "json" }.orEmpty().map { it.nameWithoutExtension }.toSet()
        assertEquals(played, files)
    }

    private fun play(name: String) = runTest {
        val fixture = Json.parseToJsonElement(File(fixtures(), "$name.json").readText()) as JsonObject
        with(Player(name, fixture)) { runIn() }
    }

    private inner class Player(private val name: String, private val fixture: JsonObject) {
        private val server = FakeWs2Server()
        private val media = FakeCallMedia()
        private var seenFrames = 0
        private var seenTexts = 0
        private var stepIndex = 0

        suspend fun TestScope.runIn() {
            val connector = FakeConnector(listOf(server))
            val connection = CallConnection(
                fixture["conversationId"].str ?: "conv",
                fixture["signalingUrl"].str ?: "wss://sig.test/ws",
                fixture["selfId"].long ?: 10,
            )
            val role = CallRole.valueOf(fixture["role"].str!!)
            val call = CallSession(
                connection, role, fixture["isGroup"].bool == true, media, connector.connector, backgroundScope, timing,
                now = { testScheduler.currentTime },
            )
            for (step in fixture["steps"].arr.orEmpty()) {
                stepIndex++
                val obj = step as JsonObject
                when {
                    obj.containsKey("do") -> when (val action = obj["do"].str) {
                        "start" -> call.start()
                        "accept" -> call.accept(obj["video"].bool == true)
                        "hangUp" -> call.hangUp()
                        else -> fail(where("неизвестное действие $action"))
                    }
                    obj.containsKey("receive") -> server.deliver(obj["receive"]!!)
                    obj.containsKey("receiveText") -> server.deliver(obj["receiveText"].str!!)
                    obj.containsKey("peerEvent") -> peerEvent(obj["peerEvent"] as JsonObject)
                    obj.containsKey("expect") -> {
                        runCurrent()
                        check(call, obj["expect"] as JsonObject)
                    }
                    else -> fail(where("неизвестный шаг $obj"))
                }
                runCurrent()
            }
        }

        private fun peerEvent(event: JsonObject) {
            val peer = media.peer ?: return fail(where("событие WebRTC без соединения"))
            event["candidate"]?.let {
                peer.emit(PeerEvent.Candidate(IceCandidate(it["sdp"].str!!, it["sdpMid"].str, (it["sdpMLineIndex"].long ?: 0).toInt())))
            }
            event["state"].str?.let { peer.emit(PeerEvent.State(PeerState.valueOf(it))) }
        }

        private fun check(call: CallSession, expect: JsonObject) {
            val state = call.state.value
            expect["phase"].str?.let { assertEquals(where("фаза"), it, state.phase::class.simpleName) }
            expect["ended"].str?.let {
                val reason = (state.phase as? CallPhase.Ended)?.reason
                assertEquals(where("причина конца"), it, reason?.let { r -> r::class.simpleName })
            }
            expect["mediaConnected"].bool?.let { assertEquals(where("mediaConnected"), it, state.mediaConnected) }
            expect["socketClosed"].bool?.let { assertEquals(where("сокет закрыт"), it, server.isClosed) }
            expect["sent"]?.let { expected ->
                val fresh = server.frames.drop(seenFrames).filter { it["command"] != null }
                val wanted = expected.arr.orEmpty()
                assertEquals(where("команды: ${fresh.map { it["command"].str }}"), wanted.size, fresh.size)
                wanted.forEachIndexed { index, frame ->
                    assertTrue(where("команда ${index + 1}: ждали $frame, ушло ${fresh[index]}"), matches(frame, fresh[index]))
                }
                seenFrames = server.frames.size
            }
            expect["sentTexts"]?.let { expected ->
                val fresh = server.texts.drop(seenTexts).filter { runCatching { Json.parseToJsonElement(it) as JsonObject }.isFailure }
                assertEquals(where("текстовые кадры"), expected.arr.orEmpty().map { it.str }, fresh)
                seenTexts = server.texts.size
            }
            if (expect.containsKey("peer")) checkPeer(expect["peer"]!!)
        }

        private fun checkPeer(expected: JsonElement) {
            val peer = media.peer
            if (expected is JsonNull) {
                assertNull(where("соединения WebRTC ещё быть не должно"), peer)
                return
            }
            assertNotNull(where("нет соединения WebRTC"), peer)
            peer!!
            expected["microphone"].bool?.let { assertEquals(where("микрофон"), it, peer.microphone) }
            expected["iceServers"].long?.let { assertEquals(where("ICE-серверы"), it.toInt(), peer.iceServers.size) }
            expected["remotes"].arr?.let { remotes ->
                assertEquals(where("удалённые SDP"), remotes.map { it.str }, peer.remotes.map { it.type.raw })
            }
            expected["candidates"].arr?.let { candidates ->
                val actual = peer.candidates.map {
                    JsonObject(
                        mapOf(
                            "sdp" to JsonPrimitive(it.sdp),
                            "sdpMid" to (it.sdpMid?.let(::JsonPrimitive) ?: JsonNull),
                            "sdpMLineIndex" to JsonPrimitive(it.sdpMLineIndex),
                        ),
                    )
                }
                assertEquals(where("кандидаты собеседника: $actual"), candidates.size, actual.size)
                candidates.forEachIndexed { index, candidate ->
                    assertTrue(where("кандидат ${index + 1}: ждали $candidate, есть ${actual[index]}"), matches(candidate, actual[index]))
                }
            }
        }

        private fun where(what: String) = "$name, шаг $stepIndex: $what"
    }

    private fun fixtures(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "test-fixtures/calls/ws2")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        error("нет каталога test-fixtures/calls/ws2 выше ${File("").absolutePath}")
    }

    companion object {
        /** Кадр совпадает, если совпадает каждое поле фикстуры; лишние поля кадра не важны. */
        internal fun matches(expected: JsonElement, actual: JsonElement?): Boolean = when (expected) {
            is JsonNull -> actual == null || actual is JsonNull
            is JsonObject -> actual is JsonObject && expected.all { (key, value) -> matches(value, actual[key]) }
            is JsonArray -> actual is JsonArray && actual.size == expected.size && expected.indices.all { matches(expected[it], actual[it]) }
            is JsonPrimitive -> when {
                actual !is JsonPrimitive || actual is JsonNull -> false
                expected.isString -> actual.isString && actual.content == expected.content
                expected.doubleOrNull != null -> !actual.isString && actual.doubleOrNull == expected.doubleOrNull
                else -> !actual.isString && actual.content == expected.content
            }
        }
    }
}
