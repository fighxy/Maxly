import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("Звонок: ws2 и WebRTC")
@MainActor
struct CallSessionTests {
    private let selfId: Int64 = 10
    private let peerId: Int64 = 20

    private func connection(video: Bool = false, ice: [CallIceServer] = []) -> CallConnection {
        CallConnection(
            conversationId: "conv",
            signalingURL: URL(string: "wss://sig.test/ws?userId=10&token=t")!,
            selfId: selfId,
            iceServers: ice,
            isVideo: video
        )
    }

    private func timing() -> CallSession.Timing {
        var timing = CallSession.Timing()
        timing.wake = .seconds(60)
        timing.gathering = .milliseconds(20)
        timing.reconnect = [.milliseconds(5), .milliseconds(5)]
        timing.levels = .seconds(60)
        return timing
    }

    private func session(
        role: CallRole,
        servers: [FakeWs2Server],
        media: FakeCallMedia,
        isGroup: Bool = false,
        timing: CallSession.Timing? = nil
    ) -> (CallSession, FakeConnector) {
        let connector = FakeConnector(servers)
        let call = CallSession(
            connection: connection(), role: role, isGroup: isGroup, media: media,
            connector: connector.connector, timing: timing ?? self.timing()
        )
        return (call, connector)
    }

    /// `connection` на двоих: мы и собеседник.
    private func connectionNotice(topology: String = "DIRECT", peerMedia: [String: JSONValue] = ["isAudioEnabled": true]) -> [String: JSONValue] {
        [
            "conversation": [
                "id": "conv",
                "topology": .string(topology),
                "participants": [
                    ["id": .int(selfId), "state": "ACCEPTED"],
                    [
                        "id": .int(peerId), "state": "CALLED", "externalId": ["id": "777", "type": "USER"],
                        "mediaSettings": .object(peerMedia), "responderTypes": ["USER"], "responderDeviceIdxs": [3],
                    ],
                ],
            ],
            "conversationParams": [
                "stun": ["urls": ["stun:stun.test:3478"]],
                "turn": ["urls": ["turn:turn.test:3478"], "username": "u", "credential": "p"],
            ],
        ]
    }

    @Test("Исходящий напрямую: офер собеседнику, гудки, ответ, кандидаты, разговор")
    func outgoingDirect() async throws {
        let server = FakeWs2Server()
        let media = FakeCallMedia()
        let (call, _) = session(role: .caller, servers: [server], media: media)
        var phases: [CallState.Phase] = []
        call.onChange = { phases.append($0.phase) }
        await call.start()
        #expect(call.state.phase == .connecting)

        server.notify("connection", connectionNotice())
        #expect(await settle { server.commands("accept-call").count == 1 })
        let peer = try #require(media.peer)
        #expect(peer.iceServers.count == 2)
        #expect(peer.microphone)
        #expect(peer.receivers == 1)
        #expect(call.state.phase == .ringing)
        let offer = try #require(server.commands("transmit-data").first)
        #expect(offer["participantId"] == .int(peerId))
        #expect(offer["deviceIdx"] == .int(3))
        #expect(offer["data"]?["sdp"]?["type"]?.string == "offer")
        #expect(call.state.participants.first { !$0.isSelf }?.userId == "777")

        // Кандидат собеседника до его ответа ждёт удалённого SDP.
        server.notify("transmitted-data", ["data": ["candidate": ["candidate": "candidate:9 1 udp 1 1.2.3.4 5 typ host", "sdpMid": "0", "sdpMLineIndex": 0]]])
        try await Task.sleep(for: .milliseconds(20))
        #expect(peer.candidates.isEmpty)

        server.notify("accepted-call", ["participantId": .int(peerId)])
        #expect(await settle { call.state.phase == .active })
        server.notify("transmitted-data", ["data": ["sdp": ["type": "answer", "sdp": "v=0 answer"]]])
        #expect(await settle { peer.remotes.count == 1 && peer.candidates.count == 1 })
        #expect(peer.remotes.first?.type == .answer)

        // Свой кандидат уходит собеседнику.
        peer.emit(.candidate(IceCandidate(sdp: "candidate:1 1 udp 1 10.0.0.1 9 typ host", sdpMid: "0", sdpMLineIndex: 0)))
        #expect(await settle { server.commands("transmit-data").count == 2 })
        peer.emit(.state(.connected))
        #expect(call.state.mediaConnected)
        #expect(call.state.activeSince != nil)

        await call.hangUp()
        #expect(call.state.phase == .ended(.hungUp))
        #expect(server.commands("hangup").first?["reason"]?.string == "HUNGUP")
        #expect(peer.closed)
        #expect(media.shutDown)
        #expect(phases.contains(.ringing))
    }

    @Test("Исходящий: сброс до ответа — CANCELED, отказ собеседника — «отклонён»")
    func outgoingCanceledAndDeclined() async throws {
        let first = FakeWs2Server()
        let (call, _) = session(role: .caller, servers: [first], media: FakeCallMedia())
        await call.start()
        first.notify("connection", connectionNotice())
        #expect(await settle { call.state.phase == .ringing })
        await call.hangUp()
        #expect(first.commands("hangup").first?["reason"]?.string == "CANCELED")

        let second = FakeWs2Server()
        let (declined, _) = session(role: .caller, servers: [second], media: FakeCallMedia())
        await declined.start()
        second.notify("connection", connectionNotice())
        #expect(await settle { declined.state.phase == .ringing })
        second.notify("hungup", ["participantId": .int(peerId), "reason": "REJECTED"])
        #expect(await settle { declined.state.phase == .ended(.declined) })
        #expect(await settle { second.isClosed })
    }

    @Test("Входящий: звонит до ответа, офер ждёт ответа, ответ шлёт accept-call и SDP")
    func incomingAnswered() async throws {
        let server = FakeWs2Server()
        let media = FakeCallMedia()
        let (call, _) = session(role: .callee, servers: [server], media: media)
        #expect(call.state.phase == .ringing)
        await call.start()
        server.notify("connection", connectionNotice())
        server.notify("transmitted-data", ["data": ["sdp": ["type": "offer", "sdp": "v=0 offer"]]])
        try await Task.sleep(for: .milliseconds(30))
        #expect(media.peers.isEmpty)
        #expect(server.commands("accept-call").isEmpty)
        #expect(call.state.phase == .ringing)

        await call.accept(video: true)
        #expect(await settle { server.commands("transmit-data").count == 1 })
        let peer = try #require(media.peer)
        #expect(media.cameraStarts == [.front])
        #expect(peer.sending == [.camera])
        #expect(peer.remotes.first?.type == .offer)
        let answer = try #require(server.commands("transmit-data").first)
        #expect(answer["data"]?["sdp"]?["type"]?.string == "answer")
        // Своя камера подписана для сервера.
        #expect(answer["data"]?["sdp"]?["sdp"]?.string?.contains("u10:sCAMERA") == true)
        let accept = try #require(server.commands("accept-call").first)
        #expect(accept["mediaSettings"]?["isVideoEnabled"]?.bool == true)
        #expect(call.state.phase == .active)
        await call.hangUp()
        #expect(server.commands("hangup").first?["reason"]?.string == "HUNGUP")
    }

    @Test("Входящий: звонящий сбросил — пропущенный; отклонить — REJECTED")
    func incomingMissedAndRejected() async throws {
        let server = FakeWs2Server()
        let (call, _) = session(role: .callee, servers: [server], media: FakeCallMedia())
        await call.start()
        server.notify("connection", connectionNotice())
        server.notify("hungup", ["participantId": .int(peerId)])
        #expect(await settle { call.state.phase == .ended(.missed) })

        let second = FakeWs2Server()
        let (rejected, _) = session(role: .callee, servers: [second], media: FakeCallMedia())
        await rejected.start()
        await rejected.hangUp()
        #expect(rejected.state.phase == .ended(.rejected))
        #expect(second.commands("hangup").first?["reason"]?.string == "REJECTED")
        #expect(second.isClosed)

        // Отклонить можно и до того, как сокет открылся.
        let third = FakeWs2Server()
        let (early, _) = session(role: .callee, servers: [third], media: FakeCallMedia())
        await early.hangUp()
        #expect(third.commands("hangup").first?["reason"]?.string == "REJECTED")
    }

    @Test("Через сервер (SFU): allocate-consumer, офер сервера, accept-producer с ssrc и сессией")
    func serverTopology() async throws {
        let server = FakeWs2Server()
        let media = FakeCallMedia()
        let (call, _) = session(role: .joiner, servers: [server], media: media, isGroup: true)
        await call.start()
        server.notify("connection", connectionNotice(topology: "SERVER"))
        #expect(await settle { server.commands("allocate-consumer").count == 1 })
        #expect(server.commandNames.prefix(2) == ["accept-call", "allocate-consumer"])
        let peer = try #require(media.peer)
        #expect(peer.channels.map(\.label) == ["producerCommand", "producerNotification"])
        #expect(call.state.topology == .server)

        let offer = "v=0\r\nm=audio 9 X 111\r\na=mid:0\r\na=ssrc:555 cname:a\r\na=candidate:1 1 udp 1 1.1.1.1 1 typ host\r\nm=video 9 X 96\r\na=mid:1\r\na=recvonly\r\n"
        server.notify("producer-updated", ["sessionId": 7, "description": ["type": "offer", "sdp": .string(offer)]])
        #expect(await settle { server.commands("accept-producer").count == 1 })
        let accepted = try #require(server.commands("accept-producer").first)
        #expect(accepted["ssrcs"] == ["555"])
        #expect(accepted["sessionId"] == .int(7))
        #expect(accepted["description"]?.string == peer.answerSdp)
        #expect(peer.candidates.map(\.sdpMid) == ["0"])
        // Камера выключена — слот не занимается.
        #expect(peer.slots.isEmpty)

        peer.emit(.state(.connected))
        #expect(call.state.phase == .active)
        // Видео участника приходит слотом: слот → ключ дорожки по каналу уведомлений.
        server.notify("participant-joined", ["participant": ["id": 30, "externalId": ["id": "888"], "mediaSettings": ["isVideoEnabled": true, "isAudioEnabled": true]]])
        #expect(await settle { call.state.participants.contains { $0.id == 30 } })
        let notifications = try #require(peer.channels.last)
        var aliases = MessagePackWriter()
        aliases.mapHeader(1)
        aliases.string("u30:sCAMERA")
        aliases.int(4)
        notifications.onMessage?(Data([1]) + aliases.data)
        var slots = MessagePackWriter()
        slots.arrayHeader(1)
        slots.int(4)
        notifications.onMessage?(Data([2]) + slots.data)
        peer.emit(.remoteTrack(RemoteTrack(id: "video-pat-0", kind: .video)))
        let member = try #require(call.state.participants.first { $0.id == 30 })
        #expect(member.cameraTrack == "video-pat-0")
        #expect(member.visibleTrack == "video-pat-0")
        #expect(member.userId == "888")

        // Раскладка видео уходит, когда открылся канал команд.
        let command = try #require(peer.channels.first)
        command.open()
        #expect(command.sent.count == 1)

        // Сервер сменил сессию — соединение пересобирается.
        server.notify("producer-updated", ["sessionId": 8, "description": .string(offer)])
        #expect(await settle { server.commands("accept-producer").count == 2 })
        #expect(media.peers.count == 2)
        #expect(peer.closed)
        await call.hangUp()
    }

    @Test("Микрофон, камера, громкая связь и экран: настройки уходят серверу")
    func mediaControls() async throws {
        let server = FakeWs2Server()
        let media = FakeCallMedia()
        let (call, _) = session(role: .caller, servers: [server], media: media)
        await call.start()
        server.notify("connection", connectionNotice())
        #expect(await settle { media.peer != nil && server.commands("accept-call").count == 1 })
        let peer = try #require(media.peer)

        await call.setMuted(true)
        #expect(call.state.muted)
        #expect(!media.microphone)
        #expect(server.commands("change-media-settings").last?["mediaSettings"]?["isAudioEnabled"]?.bool == false)
        #expect(call.state.participants.first { $0.isSelf }?.audioOn == false)

        let offersBefore = peer.offers.count
        await call.setCamera(true)
        #expect(call.state.cameraOn)
        #expect(call.state.localTrack == "cam-track")
        // Новый отправитель видео напрямую требует нового офера.
        #expect(peer.offers.count == offersBefore + 1)
        #expect(server.commands("change-media-settings").last?["mediaSettings"]?["isVideoEnabled"]?.bool == true)

        await call.switchCamera()
        #expect(call.state.camera == .back)
        #expect(media.cameraStarts == [.front, .back])

        call.setSpeaker(true)
        #expect(media.speaker)
        #expect(call.state.speakerOn)

        await call.setScreenSharing(true)
        #expect(call.state.localTrack == "screen-track")
        #expect(server.commands("change-media-settings").last?["mediaSettings"]?["isScreenSharingEnabled"]?.bool == true)

        await call.setCamera(false)
        #expect(peer.stopped == [.camera])
        #expect(!call.state.cameraOn)

        // Камеры нет — понятное сообщение, звонок идёт дальше.
        media.cameraError = .denied
        await call.setCamera(true)
        #expect(call.state.notice == "Нет доступа к камере")
        #expect(!call.state.isEnded)

        // Админ выключил нам микрофон.
        await call.setMuted(false)
        server.notify("mute-participant", ["participantId": .int(selfId), "muteStates": ["AUDIO": "MUTE"]])
        #expect(await settle { call.state.muted })
        await call.hangUp()
    }

    @Test("Участники и видео собеседника по подписи дорожки")
    func participantsAndTracks() async throws {
        let server = FakeWs2Server()
        let media = FakeCallMedia()
        let (call, _) = session(role: .caller, servers: [server], media: media)
        await call.start()
        server.notify("connection", connectionNotice(peerMedia: ["isAudioEnabled": false, "isVideoEnabled": true]))
        #expect(await settle { media.peer != nil })
        let peer = try #require(media.peer)
        var other: CallParticipant? { call.state.participants.first { $0.id == peerId } }
        #expect(other?.audioOn == false)
        #expect(other?.videoOn == true)

        peer.emit(.remoteTrack(RemoteTrack(id: "random-camera", kind: .video)))
        #expect(other?.cameraTrack == "random-camera")
        peer.emit(.remoteTrack(RemoteTrack(id: "u20:sSCREEN", kind: .video)))
        #expect(other?.screenTrack == "u20:sSCREEN")
        peer.emit(.remoteTrack(RemoteTrack(id: "audio-only", kind: .audio)))

        server.notify("media-settings-changed", ["participantId": .int(peerId), "mediaSettings": ["isAudioEnabled": true, "isScreenSharingEnabled": true]])
        #expect(await settle { other?.screenOn == true })
        #expect(other?.visibleTrack == "u20:sSCREEN")
        server.notify("roles-changed", ["participantId": .int(peerId), "roles": ["ADMIN"]])
        #expect(await settle { other?.isAdmin == true })
        server.notify("participant-state-changed", ["participantId": .int(peerId), "participantState": ["state": ["hand": "1"]]])
        #expect(await settle { other?.handRaised == true })
        server.notify("participant-left", ["participantId": .int(peerId)])
        #expect(await settle { call.state.phase == .ended(.remoteHungUp) })
    }

    @Test("Сервер закрыл разговор или сказал conversation-ended — звонок кончается")
    func serverEnds() async throws {
        let server = FakeWs2Server()
        let (call, _) = session(role: .caller, servers: [server], media: FakeCallMedia())
        await call.start()
        server.notify("connection", connectionNotice())
        server.notify("accepted-call")
        #expect(await settle { call.state.phase == .active })
        server.notify("closed-conversation")
        #expect(await settle { call.state.phase == .ended(.remoteHungUp) })

        let other = FakeWs2Server()
        other.fail("change-media-settings", with: "conversation-ended")
        let (ended, _) = session(role: .caller, servers: [other], media: FakeCallMedia())
        await ended.start()
        other.notify("connection", connectionNotice())
        #expect(await settle { other.commands("accept-call").count == 1 })
        await ended.setMuted(true)
        #expect(await settle { ended.state.phase == .ended(.noAnswer) })
    }

    @Test("Сервер молчит: сначала change-media-settings, потом accept-call")
    func wakesSilentServer() async throws {
        let server = FakeWs2Server()
        var fast = timing()
        fast.wake = .milliseconds(20)
        let (call, _) = session(role: .caller, servers: [server], media: FakeCallMedia(), timing: fast)
        await call.start()
        #expect(await settle { server.commands("accept-call").count == 1 })
        #expect(server.commandNames == ["change-media-settings", "accept-call"])
        await call.hangUp()
    }

    @Test("Сокет оборвался: переподключение и новый connection; не вышло — «связь прервалась»")
    func reconnects() async throws {
        let first = FakeWs2Server()
        let second = FakeWs2Server()
        let media = FakeCallMedia()
        let (call, connector) = session(role: .caller, servers: [first, second], media: media)
        await call.start()
        first.notify("connection", connectionNotice())
        first.notify("accepted-call")
        #expect(await settle { call.state.phase == .active })
        first.close()
        #expect(await settle { connector.connections == 2 })
        second.notify("connection", connectionNotice())
        #expect(await settle { media.peers.count == 2 && second.commands("accept-call").count == 1 })
        #expect(media.peers.first?.closed == true)
        media.peer?.emit(.state(.connected))
        #expect(call.state.phase == .active)

        // Больше серверов нет: попытки кончились.
        second.close()
        #expect(await settle { call.state.phase == .ended(.connectionLost) })
    }

    @Test("Сервер звонков недоступен — звонок не начался")
    func connectFails() async {
        let (call, connector) = session(role: .caller, servers: [], media: FakeCallMedia())
        await call.start()
        #expect(connector.connections == 1)
        #expect(call.state.phase == .ended(.failed("Сервер звонков недоступен")))
    }

    @Test("Запись и приглашение — команды сервера звонков")
    func recordAndInvite() async throws {
        let server = FakeWs2Server()
        let (call, _) = session(role: .joiner, servers: [server], media: FakeCallMedia(), isGroup: true)
        await call.start()
        await call.setRecording(true)
        #expect(call.state.recording)
        #expect(server.commands("record-start").count == 1)
        try await call.invite(userIds: ["5", "6"])
        #expect(server.commands("add-participant").first?["externalIds"] == ["5", "6"])
        server.fail("record-stop", with: "not-allowed")
        await call.setRecording(false)
        #expect(call.state.recording)
        #expect(call.state.notice == "Не удалось остановить запись")
        await call.hangUp()
    }
}
