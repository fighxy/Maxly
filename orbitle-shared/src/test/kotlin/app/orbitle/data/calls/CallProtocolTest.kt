package app.orbitle.data.calls

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Протокол звонков: сокет ws2, SDP, id участников, MessagePack каналов SFU. */
@OptIn(ExperimentalCoroutinesApi::class)
class CallProtocolTest {
    @Test
    fun signalingNumbersCommandsAndRoutesReplies() = runTest {
        val server = FakeWs2Server()
        val signaling = Ws2Signaling(server, backgroundScope, timeoutMs = 1_000)
        signaling.run()
        val reply = signaling.send("accept-call", mapOf("mediaSettings" to Ws2Command.mediaSettings(true, false, false)))
        assertEquals("accept-call", reply["response"].str)
        signaling.send("hangup")
        assertEquals(listOf(1L, 2L), server.frames.map { it["sequence"].long })

        server.fail("record-start", "not-allowed")
        val error = runCatching { signaling.send("record-start") }.exceptionOrNull()
        assertTrue(error is Ws2Exception.Command && error.error == "not-allowed")
        // Ошибка приходит и уведомлением.
        assertEquals("error", signaling.notifications.receive()["type"].str)

        server.deliver("ping")
        runCurrent()
        assertEquals("pong", server.texts.last())

        server.notify("hungup", mapOf("participantId" to 5))
        runCurrent()
        assertEquals("hungup", signaling.notifications.receive()["notification"].str)
    }

    @Test
    fun silentServerTimesOutAndCloseFailsWaiters() = runTest {
        val server = object : Ws2Socket {
            val delegate = FakeWs2Server()
            override suspend fun send(text: String) = Unit
            override suspend fun receive() = delegate.receive()
            override fun close() = delegate.close()
        }
        val signaling = Ws2Signaling(server, backgroundScope, timeoutMs = 1_000)
        signaling.run()
        val timeout = async { runCatching { signaling.send("accept-call") }.exceptionOrNull() }
        advanceTimeBy(1_100)
        assertTrue(timeout.await() is Ws2Exception.Timeout)

        val waiting = async { runCatching { signaling.send("hangup") }.exceptionOrNull() }
        runCurrent()
        signaling.close()
        assertTrue(waiting.await() is Ws2Exception.Closed)
        assertTrue(signaling.isClosed)
        assertTrue(runCatching { signaling.send("hangup") }.exceptionOrNull() is Ws2Exception.Closed)
    }

    @Test
    fun commandBodies() {
        val offer = Ws2Command.transmit(SessionDescription(SdpType.OFFER, "v=0"), CallPeerAddress(20, deviceIdx = 3))
        assertEquals(20L, offer["participantId"].long)
        assertEquals("USER", offer["participantType"].str)
        assertEquals("offer", offer["data"]["sdp"]["type"].str)
        assertEquals("3c02f", offer["capabilities"].str)
        val candidate = Ws2Command.transmit(IceCandidate("candidate:1", null, 1), CallPeerAddress(20))
        assertEquals("0", candidate["data"]["candidate"]["sdpMid"].str)
        assertEquals(1L, candidate["data"]["candidate"]["sdpMLineIndex"].long)
        assertEquals(false, Ws2Command.recordStart["streamMovie"].bool)
        assertEquals(10L, Ws2Command.allocateConsumer["capabilities"]["videoTracksCount"].long)
    }

    @Test
    fun sdpParsing() {
        val sdp = "v=0\r\nm=audio 9 X 111\r\na=mid:0\r\na=ssrc:555 cname:a\r\na=ssrc:555 msid:s t\r\na=ssrc:777 cname:b\r\n" +
            "a=candidate:1 1 udp 1 1.1.1.1 1 typ host\r\na=candidate:1 1 udp 1 1.1.1.1 1 typ host\r\n" +
            "m=video 9 X 96\r\na=mid:1\r\na=recvonly\r\nm=video 9 X 96\r\na=mid:2\r\na=sendrecv\r\n"
        assertEquals(listOf("555", "777"), CallSdp.ssrcs(sdp))
        assertEquals(listOf(IceCandidate("candidate:1 1 udp 1 1.1.1.1 1 typ host", "0", 0)), CallSdp.candidates(sdp))
        assertEquals(setOf("1"), CallSdp.receiveOnlyVideoMids(sdp))
        assertEquals("abcd", CallSdp.iceUfrag("v=0\r\na=ice-ufrag:abcd\r\na=ice-pwd:x\r\na=ice-ufrag:efgh"))
        assertEquals(null, CallSdp.iceUfrag("v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111"))

        val labeled = CallSdp.label("a=msid:stream cam\r\na=ssrc:1 msid:stream cam\r\na=ssrc:1 label:cam\r\na=msid:stream mic", mapOf("cam" to "u10:sCAMERA"))
        assertEquals("a=msid:stream u10:sCAMERA\r\na=ssrc:1 msid:stream u10:sCAMERA\r\na=ssrc:1 label:u10:sCAMERA\r\na=msid:stream mic", labeled)
    }

    @Test
    fun participantIdsAndTrackOwners() {
        assertEquals(123L, CallSdp.participantId(JsonPrimitive(123)))
        assertEquals(123L, CallSdp.participantId(JsonPrimitive("u123:d0")))
        assertEquals(55L, CallSdp.participantId(JsonPrimitive("g55")))
        assertEquals(77L, CallSdp.participantId(JsonPrimitive("77")))
        assertNull(CallSdp.participantId(JsonPrimitive("d1")))
        assertEquals(TrackOwner(participant = 5, screen = true), CallSdp.owner("u5:sSCREEN"))
        assertEquals(TrackOwner(participant = 5), CallSdp.owner("u5:sCAMERA"))
        assertEquals(TrackOwner(slot = 3), CallSdp.owner("video-pat-3"))
        assertEquals(TrackOwner(participant = 9), CallSdp.owner("video-9"))
        assertEquals(TrackOwner(), CallSdp.owner("random"))
        assertEquals("u5:sCAMERA", CallSdp.layoutKey(5, screen = false))
    }

    @Test
    fun messagePackChannels() {
        val layout = SfuChannel.displayLayout(listOf(SfuChannel.LayoutItem("u5:sCAMERA")), sequence = 1)
        val reader = MessagePackReader(layout)
        assertEquals(0L, reader.int())
        assertEquals(0L, reader.int())
        assertEquals(1L, reader.int())
        assertEquals(0xC3, layout[3].toInt() and 0xFF)
        val empty = SfuChannel.displayLayout(emptyList(), sequence = 2)
        assertEquals(listOf(0, 0, 2, 0xC3, 0xC0, 0xC0), empty.map { it.toInt() and 0xFF })

        val aliases = MessagePackWriter().apply {
            mapHeader(1)
            string("u5:sCAMERA")
            int(300)
        }
        val parsed = SfuChannel.parse(byteArrayOf(1) + aliases.bytes(), emptyMap()) as SfuChannel.Notification.Aliases
        assertEquals(mapOf(300 to "u5:sCAMERA"), parsed.map)
        val levels = MessagePackWriter().apply {
            mapHeader(1)
            int(300)
            int(90)
        }
        assertEquals(SfuChannel.Notification.Levels(mapOf("u5:sCAMERA" to 90)), SfuChannel.parse(byteArrayOf(6) + levels.bytes(), parsed.map))
        assertNull(SfuChannel.parse(byteArrayOf(1, 0xC1.toByte()), emptyMap()))
        val negative = MessagePackWriter().apply { int(-200) }
        assertEquals(-200L, MessagePackReader(negative.bytes()).int())
    }

    @Test
    fun iceServersFromConnection() {
        val servers = CallSession.iceServers(
            element(mapOf("stun" to mapOf("urls" to "stun:a"), "turn" to mapOf("urls" to listOf("turn:b"), "username" to "u", "credential" to "p"))),
        )!!
        assertEquals(listOf("stun:a"), servers[0].urls)
        assertEquals("u", servers[1].username)
        assertNull(CallSession.iceServers(element(mapOf("stun" to mapOf("urls" to emptyList<String>())))))
    }
}
