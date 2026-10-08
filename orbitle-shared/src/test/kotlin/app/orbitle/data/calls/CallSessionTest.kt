package app.orbitle.data.calls

import app.orbitle.domain.CallCameraPosition
import app.orbitle.domain.CallConnection
import app.orbitle.domain.CallEndReason
import app.orbitle.domain.CallPhase
import app.orbitle.domain.CallRole
import app.orbitle.domain.CallTopology
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Звонок: ws2 и WebRTC на фейковом сервере и фейковом WebRTC. Порт iOS `CallSessionTests`. */
@OptIn(ExperimentalCoroutinesApi::class)
class CallSessionTest {
    private val selfId = 10L
    private val peerId = 20L
    private val timing = CallSession.Timing(wake = 60_000, gathering = 20, reconnect = listOf(5, 5), levels = 60_000)

    private fun TestScope.session(
        role: CallRole,
        servers: List<FakeWs2Server>,
        media: FakeCallMedia,
        isGroup: Boolean = false,
        timing: CallSession.Timing = this@CallSessionTest.timing,
    ): Pair<CallSession, FakeConnector> {
        val connector = FakeConnector(servers)
        val connection = CallConnection("conv", "wss://sig.test/ws?userId=10&token=t", selfId)
        return CallSession(connection, role, isGroup, media, connector.connector, backgroundScope, timing, now = { testScheduler.currentTime }) to connector
    }

    /** `connection` на двоих: мы и собеседник. */
    private fun connectionNotice(topology: String = "DIRECT", peerMedia: Map<String, Any?> = mapOf("isAudioEnabled" to true)) = mapOf(
        "conversation" to mapOf(
            "id" to "conv",
            "topology" to topology,
            "participants" to listOf(
                mapOf("id" to selfId, "state" to "ACCEPTED"),
                mapOf(
                    "id" to peerId, "state" to "CALLED", "externalId" to mapOf("id" to "777", "type" to "USER"),
                    "mediaSettings" to peerMedia, "responderTypes" to listOf("USER"), "responderDeviceIdxs" to listOf(3),
                ),
            ),
        ),
        "conversationParams" to mapOf(
            "stun" to mapOf("urls" to listOf("stun:stun.test:3478")),
            "turn" to mapOf("urls" to listOf("turn:turn.test:3478"), "username" to "u", "credential" to "p"),
        ),
    )

    @Test
    fun outgoingDirect() = runTest {
        val server = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, _) = session(CallRole.CALLER, listOf(server), media)
        call.start()
        assertEquals(CallPhase.Connecting, call.state.value.phase)

        server.notify("connection", connectionNotice())
        runCurrent()
        assertEquals(1, server.commands("accept-call").size)
        val peer = assertNotNull(media.peer).let { media.peer!! }
        assertEquals(2, peer.iceServers.size)
        assertTrue(peer.microphone)
        assertEquals(1, peer.receivers)
        assertEquals(CallPhase.Ringing, call.state.value.phase)
        val offer = server.commands("transmit-data").first()
        assertEquals(peerId, offer["participantId"].long)
        assertEquals(3L, offer["deviceIdx"].long)
        assertEquals("offer", offer["data"]["sdp"]["type"].str)
        assertEquals("777", call.state.value.participants.first { !it.isSelf }.userId)

        // Кандидат собеседника до его ответа ждёт удалённого SDP.
        server.notify("transmitted-data", mapOf("data" to mapOf("candidate" to mapOf("candidate" to "candidate:9 1 udp 1 1.2.3.4 5 typ host", "sdpMid" to "0", "sdpMLineIndex" to 0))))
        runCurrent()
        assertTrue(peer.candidates.isEmpty())

        server.notify("accepted-call", mapOf("participantId" to peerId))
        runCurrent()
        assertEquals(CallPhase.Active, call.state.value.phase)
        server.notify("transmitted-data", mapOf("data" to mapOf("sdp" to mapOf("type" to "answer", "sdp" to "v=0 answer"))))
        runCurrent()
        assertEquals(1, peer.remotes.size)
        assertEquals(1, peer.candidates.size)
        assertEquals(SdpType.ANSWER, peer.remotes.first().type)

        // Свой кандидат уходит собеседнику.
        peer.emit(PeerEvent.Candidate(IceCandidate("candidate:1 1 udp 1 10.0.0.1 9 typ host", "0", 0)))
        runCurrent()
        assertEquals(2, server.commands("transmit-data").size)
        peer.emit(PeerEvent.State(PeerState.CONNECTED))
        assertTrue(call.state.value.mediaConnected)
        assertNotNull(call.state.value.activeSinceMs)

        call.hangUp()
        assertEquals(CallPhase.Ended(CallEndReason.HungUp), call.state.value.phase)
        assertEquals("HUNGUP", server.commands("hangup").first()["reason"].str)
        assertTrue(peer.closed)
        assertTrue(media.shutDown)
    }

    @Test
    fun outgoingCanceledAndDeclined() = runTest {
        val first = FakeWs2Server()
        val (call, _) = session(CallRole.CALLER, listOf(first), FakeCallMedia())
        call.start()
        first.notify("connection", connectionNotice())
        runCurrent()
        assertEquals(CallPhase.Ringing, call.state.value.phase)
        call.hangUp()
        assertEquals("CANCELED", first.commands("hangup").first()["reason"].str)

        val second = FakeWs2Server()
        val (declined, _) = session(CallRole.CALLER, listOf(second), FakeCallMedia())
        declined.start()
        second.notify("connection", connectionNotice())
        runCurrent()
        second.notify("hungup", mapOf("participantId" to peerId, "reason" to "REJECTED"))
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.Declined), declined.state.value.phase)
        assertTrue(second.isClosed)
    }

    @Test
    fun incomingAnswered() = runTest {
        val server = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, _) = session(CallRole.CALLEE, listOf(server), media)
        assertEquals(CallPhase.Ringing, call.state.value.phase)
        call.start()
        server.notify("connection", connectionNotice())
        server.notify("transmitted-data", mapOf("data" to mapOf("sdp" to mapOf("type" to "offer", "sdp" to "v=0 offer"))))
        runCurrent()
        assertTrue(media.peers.isEmpty())
        assertTrue(server.commands("accept-call").isEmpty())
        assertEquals(CallPhase.Ringing, call.state.value.phase)

        call.accept(video = true)
        runCurrent()
        assertEquals(1, server.commands("transmit-data").size)
        val peer = media.peer!!
        assertEquals(listOf(CallCameraPosition.FRONT), media.cameraStarts)
        assertEquals(listOf(LocalVideo.CAMERA), peer.sending)
        assertEquals(SdpType.OFFER, peer.remotes.first().type)
        val answer = server.commands("transmit-data").first()
        assertEquals("answer", answer["data"]["sdp"]["type"].str)
        // Своя камера подписана для сервера.
        assertTrue(answer["data"]["sdp"]["sdp"].str!!.contains("u10:sCAMERA"))
        assertEquals(true, server.commands("accept-call").first()["mediaSettings"]["isVideoEnabled"].bool)
        assertEquals(CallPhase.Active, call.state.value.phase)
        call.hangUp()
        assertEquals("HUNGUP", server.commands("hangup").first()["reason"].str)
    }

    @Test
    fun incomingMissedAndRejected() = runTest {
        val server = FakeWs2Server()
        val (call, _) = session(CallRole.CALLEE, listOf(server), FakeCallMedia())
        call.start()
        server.notify("connection", connectionNotice())
        server.notify("hungup", mapOf("participantId" to peerId))
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.Missed), call.state.value.phase)

        val second = FakeWs2Server()
        val (rejected, _) = session(CallRole.CALLEE, listOf(second), FakeCallMedia())
        rejected.start()
        rejected.hangUp()
        assertEquals(CallPhase.Ended(CallEndReason.Rejected), rejected.state.value.phase)
        assertEquals("REJECTED", second.commands("hangup").first()["reason"].str)
        assertTrue(second.isClosed)

        // Отклонить можно и до того, как сокет открылся.
        val third = FakeWs2Server()
        val (early, _) = session(CallRole.CALLEE, listOf(third), FakeCallMedia())
        early.hangUp()
        assertEquals("REJECTED", third.commands("hangup").first()["reason"].str)
    }

    @Test
    fun serverTopology() = runTest {
        val server = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, _) = session(CallRole.JOINER, listOf(server), media, isGroup = true)
        call.start()
        server.notify("connection", connectionNotice(topology = "SERVER"))
        runCurrent()
        assertEquals(listOf("accept-call", "allocate-consumer"), server.commandNames.take(2))
        val peer = media.peer!!
        assertEquals(listOf("producerCommand", "producerNotification"), peer.channels.map { it.label })
        assertEquals(CallTopology.SERVER, call.state.value.topology)

        val offer = "v=0\r\nm=audio 9 X 111\r\na=mid:0\r\na=ssrc:555 cname:a\r\na=candidate:1 1 udp 1 1.1.1.1 1 typ host\r\nm=video 9 X 96\r\na=mid:1\r\na=recvonly\r\n"
        server.notify("producer-updated", mapOf("sessionId" to 7, "description" to mapOf("type" to "offer", "sdp" to offer)))
        runCurrent()
        advanceTimeBy(30)
        runCurrent()
        val accepted = server.commands("accept-producer").single()
        assertEquals(listOf("555"), accepted["ssrcs"].arr!!.map { it.str })
        assertEquals(7L, accepted["sessionId"].long)
        assertEquals(peer.answerSdp, accepted["description"].str)
        assertEquals(listOf("0"), peer.candidates.map { it.sdpMid })
        // Камера выключена — слот не занимается.
        assertTrue(peer.slots.isEmpty())

        peer.emit(PeerEvent.State(PeerState.CONNECTED))
        assertEquals(CallPhase.Active, call.state.value.phase)
        // Видео участника приходит слотом: слот → ключ дорожки по каналу уведомлений.
        server.notify(
            "participant-joined",
            mapOf("participant" to mapOf("id" to 30, "externalId" to mapOf("id" to "888"), "mediaSettings" to mapOf("isVideoEnabled" to true, "isAudioEnabled" to true))),
        )
        runCurrent()
        val notifications = peer.channels.last()
        val aliases = MessagePackWriter().apply {
            mapHeader(1)
            string("u30:sCAMERA")
            int(4)
        }
        notifications.onMessage?.invoke(byteArrayOf(1) + aliases.bytes())
        val slots = MessagePackWriter().apply {
            arrayHeader(1)
            int(4)
        }
        notifications.onMessage?.invoke(byteArrayOf(2) + slots.bytes())
        peer.emit(PeerEvent.Track(RemoteTrack("video-pat-0", MediaKind.VIDEO)))
        val member = call.state.value.participants.first { it.id == 30L }
        assertEquals("video-pat-0", member.cameraTrack)
        assertEquals("video-pat-0", member.visibleTrack)
        assertEquals("888", member.userId)

        // Раскладка видео уходит, когда открылся канал команд.
        val command = peer.channels.first()
        command.open()
        assertEquals(1, command.sent.size)

        // Сервер сменил сессию — соединение пересобирается.
        server.notify("producer-updated", mapOf("sessionId" to 8, "description" to offer))
        runCurrent()
        advanceTimeBy(30)
        runCurrent()
        assertEquals(2, server.commands("accept-producer").size)
        assertEquals(2, media.peers.size)
        assertTrue(peer.closed)
        call.hangUp()
    }

    @Test
    fun mediaControls() = runTest {
        val server = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, _) = session(CallRole.CALLER, listOf(server), media)
        call.start()
        server.notify("connection", connectionNotice())
        runCurrent()
        val peer = media.peer!!

        call.setMuted(true)
        assertTrue(call.state.value.muted)
        assertFalse(media.micOn)
        assertEquals(false, server.commands("change-media-settings").last()["mediaSettings"]["isAudioEnabled"].bool)
        assertEquals(false, call.state.value.participants.first { it.isSelf }.audioOn)

        val offersBefore = peer.offers.size
        call.setCamera(true)
        assertTrue(call.state.value.cameraOn)
        assertEquals("cam-track", call.state.value.localTrack)
        // Новый отправитель видео напрямую требует нового офера.
        assertEquals(offersBefore + 1, peer.offers.size)
        assertEquals(true, server.commands("change-media-settings").last()["mediaSettings"]["isVideoEnabled"].bool)

        call.switchCamera()
        assertEquals(CallCameraPosition.BACK, call.state.value.camera)
        assertEquals(listOf(CallCameraPosition.FRONT, CallCameraPosition.BACK), media.cameraStarts)

        call.setSpeaker(true)
        assertTrue(media.speakerOn)
        assertTrue(call.state.value.speakerOn)

        call.setScreenSharing(true)
        assertEquals("screen-track", call.state.value.localTrack)
        assertEquals(true, server.commands("change-media-settings").last()["mediaSettings"]["isScreenSharingEnabled"].bool)

        call.setCamera(false)
        assertEquals(listOf(LocalVideo.CAMERA), peer.stopped)
        assertFalse(call.state.value.cameraOn)

        // Камеры нет — понятное сообщение, звонок идёт дальше.
        media.cameraError = CallMediaException.Kind.DENIED
        call.setCamera(true)
        assertEquals("Нет доступа к камере", call.state.value.notice)
        assertFalse(call.state.value.isEnded)

        // Админ выключил нам микрофон.
        call.setMuted(false)
        server.notify("mute-participant", mapOf("participantId" to selfId, "muteStates" to mapOf("AUDIO" to "MUTE")))
        runCurrent()
        assertTrue(call.state.value.muted)
        call.hangUp()
    }

    @Test
    fun videoFailuresRollBackAndStopStillWorks() = runTest {
        val server = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, _) = session(CallRole.CALLER, listOf(server), media)
        call.start()
        server.notify("connection", connectionNotice())
        runCurrent()
        val peer = media.peer!!

        // Соединение не приняло дорожку: кнопка откатывается, человек видит сообщение.
        peer.videoError = IllegalStateException("RtpSender has been disposed.")
        call.setCamera(true)
        assertFalse(call.state.value.cameraOn)
        assertEquals("Не удалось включить камеру", call.state.value.notice)
        call.setScreenSharing(true)
        assertFalse(call.state.value.screenSharing)
        assertFalse(media.screen)
        assertEquals("Не удалось показать экран", call.state.value.notice)

        // Выключение не застревает, даже если соединение не отпускает дорожку.
        peer.videoError = null
        call.setScreenSharing(true)
        assertTrue(call.state.value.screenSharing)
        peer.videoError = IllegalStateException("RtpSender has been disposed.")
        call.setScreenSharing(false)
        assertFalse(call.state.value.screenSharing)
        assertFalse(media.screen)
        assertFalse(call.state.value.isEnded)
        call.hangUp()
    }

    @Test
    fun participantsAndTracks() = runTest {
        val server = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, _) = session(CallRole.CALLER, listOf(server), media)
        call.start()
        server.notify("connection", connectionNotice(peerMedia = mapOf("isAudioEnabled" to false, "isVideoEnabled" to true)))
        runCurrent()
        val peer = media.peer!!
        fun other() = call.state.value.participants.first { it.id == peerId }
        assertFalse(other().audioOn)
        assertTrue(other().videoOn)

        peer.emit(PeerEvent.Track(RemoteTrack("random-camera", MediaKind.VIDEO)))
        assertEquals("random-camera", other().cameraTrack)
        peer.emit(PeerEvent.Track(RemoteTrack("u20:sSCREEN", MediaKind.VIDEO)))
        assertEquals("u20:sSCREEN", other().screenTrack)
        peer.emit(PeerEvent.Track(RemoteTrack("audio-only", MediaKind.AUDIO)))

        server.notify("media-settings-changed", mapOf("participantId" to peerId, "mediaSettings" to mapOf("isAudioEnabled" to true, "isScreenSharingEnabled" to true)))
        runCurrent()
        assertTrue(other().screenOn)
        assertEquals("u20:sSCREEN", other().visibleTrack)
        server.notify("roles-changed", mapOf("participantId" to peerId, "roles" to listOf("ADMIN")))
        runCurrent()
        assertTrue(other().isAdmin)
        server.notify("participant-state-changed", mapOf("participantId" to peerId, "participantState" to mapOf("state" to mapOf("hand" to "1"))))
        runCurrent()
        assertTrue(other().handRaised)
        server.notify("participant-left", mapOf("participantId" to peerId))
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.RemoteHungUp), call.state.value.phase)
    }

    @Test
    fun serverEnds() = runTest {
        val server = FakeWs2Server()
        val (call, _) = session(CallRole.CALLER, listOf(server), FakeCallMedia())
        call.start()
        server.notify("connection", connectionNotice())
        server.notify("accepted-call")
        runCurrent()
        assertEquals(CallPhase.Active, call.state.value.phase)
        server.notify("closed-conversation")
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.RemoteHungUp), call.state.value.phase)

        val other = FakeWs2Server()
        other.fail("change-media-settings", "conversation-ended")
        val (ended, _) = session(CallRole.CALLER, listOf(other), FakeCallMedia())
        ended.start()
        other.notify("connection", connectionNotice())
        runCurrent()
        ended.setMuted(true)
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.NoAnswer), ended.state.value.phase)
    }

    @Test
    fun wakesSilentServer() = runTest {
        val server = FakeWs2Server()
        val (call, _) = session(CallRole.CALLER, listOf(server), FakeCallMedia(), timing = timing.copy(wake = 20))
        call.start()
        advanceTimeBy(50)
        runCurrent()
        assertEquals(listOf("change-media-settings", "accept-call"), server.commandNames)
        call.hangUp()
    }

    @Test
    fun reconnects() = runTest {
        val first = FakeWs2Server()
        val second = FakeWs2Server()
        val media = FakeCallMedia()
        val (call, connector) = session(CallRole.CALLER, listOf(first, second), media)
        call.start()
        first.notify("connection", connectionNotice())
        first.notify("accepted-call")
        runCurrent()
        assertEquals(CallPhase.Active, call.state.value.phase)
        first.close()
        runCurrent()
        assertEquals(CallPhase.Reconnecting, call.state.value.phase)
        advanceTimeBy(10)
        runCurrent()
        assertEquals(2, connector.connections)
        second.notify("connection", connectionNotice())
        runCurrent()
        assertEquals(2, media.peers.size)
        assertEquals(1, second.commands("accept-call").size)
        assertTrue(media.peers.first().closed)
        media.peer!!.emit(PeerEvent.State(PeerState.CONNECTED))
        assertEquals(CallPhase.Active, call.state.value.phase)

        // Больше серверов нет: попытки кончились.
        second.close()
        runCurrent()
        advanceTimeBy(20)
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.ConnectionLost), call.state.value.phase)
    }

    @Test
    fun connectFails() = runTest {
        val (call, connector) = session(CallRole.CALLER, emptyList(), FakeCallMedia())
        call.start()
        assertEquals(1, connector.connections)
        assertEquals(CallPhase.Ended(CallEndReason.Failed("Сервер звонков недоступен")), call.state.value.phase)
    }

    @Test
    fun recordAndInvite() = runTest {
        val server = FakeWs2Server()
        val (call, _) = session(CallRole.JOINER, listOf(server), FakeCallMedia(), isGroup = true)
        call.start()
        call.setRecording(true)
        assertTrue(call.state.value.recording)
        assertEquals(1, server.commands("record-start").size)
        call.invite(listOf("5", "6"))
        assertEquals(listOf("5", "6"), server.commands("add-participant").first()["externalIds"].arr!!.map { it.str })
        server.fail("record-stop", "not-allowed")
        call.setRecording(false)
        assertTrue(call.state.value.recording)
        assertEquals("Не удалось остановить запись", call.state.value.notice)
        call.hangUp()
    }

    @Test
    fun noAnswerCancelsAfterRing() = runTest {
        val server = FakeWs2Server()
        val (call, _) = session(CallRole.CALLER, listOf(server), FakeCallMedia(), timing = timing.copy(outgoingRing = 1_000))
        call.start()
        server.notify("connection", connectionNotice())
        runCurrent()
        advanceTimeBy(1_100)
        runCurrent()
        assertEquals(CallPhase.Ended(CallEndReason.NoAnswer), call.state.value.phase)
        assertEquals(JsonPrimitive("CANCELED"), server.commands("hangup").first()["reason"])
    }
}
