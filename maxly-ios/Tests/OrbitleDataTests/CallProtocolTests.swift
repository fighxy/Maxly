import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

@Suite("JSON сервера звонков")
struct JSONValueTests {
    @Test("Целые остаются целыми, булевы — булевыми, порядок ключей стабилен")
    func roundTrip() throws {
        let value = try #require(JSONValue.parse(#"{"a":1,"b":true,"c":1.5,"d":"x","e":[null,1700000000123],"f":{"g":false}}"#))
        #expect(value["a"] == .int(1))
        #expect(value["b"] == .bool(true))
        #expect(value["c"] == .double(1.5))
        #expect(value["d"]?.string == "x")
        #expect(value["e"]?.array?.last == .int(1_700_000_000_123))
        #expect(value["f"]?["g"]?.bool == false)
        #expect(JSONValue.object(["b": 1, "a": "s/t"]).serialized() == #"{"a":"s/t","b":1}"#)
        #expect(JSONValue.string("7").int == 7)
        #expect(JSONValue.parse("не json") == nil)
    }
}

@Suite("Сигнальный сокет ws2")
struct Ws2SignalingTests {
    @Test("Команда получает ответ по своему номеру, номера идут с 1")
    func commandResponse() async throws {
        let server = FakeWs2Server()
        let signaling = Ws2Signaling(socket: server)
        await signaling.run()
        let reply = try await signaling.send("accept-call", ["mediaSettings": ["isAudioEnabled": true]])
        #expect(reply["response"]?.string == "accept-call")
        try await signaling.send("hangup", ["reason": "HUNGUP"])
        let frames = server.frames
        #expect(frames.map { $0["sequence"]?.int } == [1, 2])
        #expect(frames[1]["reason"]?.string == "HUNGUP")
        #expect(frames[0]["mediaSettings"]?["isAudioEnabled"]?.bool == true)
        await signaling.close()
    }

    @Test("Ошибка сервера бросается и уходит в уведомления; ping получает pong")
    func errorsAndPing() async throws {
        let server = FakeWs2Server()
        server.fail("transmit-data", with: "conversation-ended")
        let signaling = Ws2Signaling(socket: server)
        await signaling.run()
        await #expect(throws: Ws2Error.command(command: "transmit-data", error: "conversation-ended")) {
            try await signaling.send("transmit-data")
        }
        var iterator = signaling.notifications.makeAsyncIterator()
        let error = await iterator.next()
        #expect(error?["error"]?.string == "conversation-ended")
        server.deliver(text: "ping")
        server.notify("hungup", ["participantId": 5])
        let hungup = await iterator.next()
        #expect(hungup?["notification"]?.string == "hungup")
        #expect(server.texts.contains("pong"))
        await signaling.close()
    }

    @Test("Закрытый сокет будит ждущие команды и кончает поток уведомлений")
    func closing() async throws {
        let server = FakeWs2Server()
        server.ignore("allocate-consumer")
        let signaling = Ws2Signaling(socket: server, timeout: .seconds(30))
        await signaling.run()
        let pending = Task { try await signaling.send("allocate-consumer") }
        _ = await eventually { server.commands("allocate-consumer").count == 1 }
        server.close()
        await #expect(throws: Ws2Error.closed) { try await pending.value }
        var iterator = signaling.notifications.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        await #expect(throws: Ws2Error.closed) { try await signaling.send("hangup") }
    }

    @Test("Без ответа команда кончается таймаутом")
    func timeout() async throws {
        let server = FakeWs2Server()
        server.ignore("request-realloc")
        let signaling = Ws2Signaling(socket: server, timeout: .milliseconds(50))
        await signaling.run()
        await #expect(throws: Ws2Error.timeout(command: "request-realloc")) {
            try await signaling.send("request-realloc")
        }
        await signaling.close()
    }

    @Test("Тела команд как у SDK звонков")
    func commandBodies() {
        let target = CallPeerAddress(id: 42, type: "USER", deviceIdx: 1)
        let sdp = Ws2Command.transmit(sdp: SessionDescription(type: .offer, sdp: "v=0"), to: target)
        #expect(sdp["participantId"] == .int(42))
        #expect(sdp["deviceIdx"] == .int(1))
        #expect(sdp["data"]?["sdp"]?["type"]?.string == "offer")
        #expect(sdp["capabilities"]?.string == "3c02f")
        let candidate = Ws2Command.transmit(candidate: IceCandidate(sdp: "candidate:1", sdpMid: nil, sdpMLineIndex: 2), to: target)
        #expect(candidate["data"]?["candidate"]?["sdpMid"]?.string == "0")
        #expect(candidate["data"]?["candidate"]?["sdpMLineIndex"] == .int(2))
        #expect(candidate["capabilities"] == nil)
        let settings = Ws2Command.mediaSettings(audio: false, video: true, screen: false)
        #expect(settings["isAudioEnabled"]?.bool == false)
        #expect(settings["isVideoEnabled"]?.bool == true)
        #expect(settings["isAnimojiEnabled"]?.bool == false)
        #expect(Ws2Command.allocateConsumer["capabilities"]?["producerNotificationDataChannelVersion"] == .int(7))
        #expect(Ws2Command.recordStart["movieId"] == .null)
    }
}

@Suite("SDP и id сервера звонков")
struct CallSdpTests {
    private let serverOffer = """
    v=0\r
    a=group:BUNDLE 0 1 2\r
    m=audio 9 UDP/TLS/RTP/SAVPF 111\r
    a=mid:0\r
    a=sendrecv\r
    a=ssrc:100 cname:x\r
    a=ssrc:100 msid:s a\r
    a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host\r
    a=candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host\r
    m=video 9 UDP/TLS/RTP/SAVPF 96\r
    a=mid:1\r
    a=recvonly\r
    m=video 9 UDP/TLS/RTP/SAVPF 96\r
    a=mid:2\r
    a=sendonly\r
    a=ssrc:200 cname:x\r
    """

    @Test("ssrc без повторов, кандидаты из SDP с mid первой секции, слоты на приём")
    func parsing() {
        #expect(CallSdp.ssrcs(in: serverOffer) == ["100", "200"])
        let candidates = CallSdp.candidates(in: serverOffer)
        #expect(candidates.count == 1)
        #expect(candidates.first?.sdp == "candidate:1 1 udp 2122260223 10.0.0.1 5000 typ host")
        #expect(candidates.first?.sdpMid == "0")
        #expect(CallSdp.receiveOnlyVideoMids(in: serverOffer) == ["1"])
    }

    @Test("Своё видео подписывается u<номер>:sCAMERA и sSCREEN")
    func labels() {
        let sdp = "a=msid:stream cam\r\na=ssrc:1 msid:stream cam\r\na=ssrc:1 label:cam\r\na=msid:stream screen\r\na=msid:stream other\r\n"
        let labeled = CallSdp.label(sdp, names: ["cam": "u7:sCAMERA", "screen": "u7:sSCREEN"])
        #expect(labeled == "a=msid:stream u7:sCAMERA\r\na=ssrc:1 msid:stream u7:sCAMERA\r\na=ssrc:1 label:u7:sCAMERA\r\na=msid:stream u7:sSCREEN\r\na=msid:stream other\r\n")
        #expect(CallSdp.label(sdp, names: [:]) == sdp)
    }

    @Test("Слот SFU подписывается по mid, какой бы id дорожки в нём ни остался")
    func slotLabels() {
        let sdp = "v=0\r\nm=audio 9 X 111\r\na=msid:s mic\r\na=mid:0\r\nm=video 9 X 96\r\na=msid:s cam\r\na=mid:1\r\na=ssrc:21 msid:s cam\r\na=ssrc:21 label:cam\r\nm=video 9 X 96\r\na=mid:2\r\na=msid:s other\r\n"
        let labeled = CallSdp.label(sdp, mids: ["1"], as: "u7:sSCREEN")
        #expect(labeled == "v=0\r\nm=audio 9 X 111\r\na=msid:s mic\r\na=mid:0\r\nm=video 9 X 96\r\na=msid:s u7:sSCREEN\r\na=mid:1\r\na=ssrc:21 msid:s u7:sSCREEN\r\na=ssrc:21 label:u7:sSCREEN\r\nm=video 9 X 96\r\na=mid:2\r\na=msid:s other\r\n")
        #expect(CallSdp.label(sdp, mids: [], as: "u7:sSCREEN") == sdp)
        #expect(CallSdp.label(sdp, mids: ["5"], as: "u7:sSCREEN") == sdp)
    }

    @Test("Номер участника из числа и из строки u/g/d")
    func participantIds() {
        #expect(CallSdp.participantId(.int(5)) == 5)
        #expect(CallSdp.participantId(.string("u123:d0")) == 123)
        #expect(CallSdp.participantId(.string("d1:g77")) == 77)
        #expect(CallSdp.participantId(.string("45")) == 45)
        #expect(CallSdp.participantId(.string("x")) == nil)
        #expect(CallSdp.participantId(nil) == nil)
    }

    @Test("Хозяин дорожки: подпись, слот SFU, префикс")
    func owners() {
        #expect(CallSdp.owner(ofTrack: "u12:sSCREEN") == TrackOwner(participant: 12, screen: true))
        #expect(CallSdp.owner(ofTrack: "u12:sCAMERA") == TrackOwner(participant: 12))
        #expect(CallSdp.owner(ofTrack: "video-pat-3") == TrackOwner(slot: 3))
        #expect(CallSdp.owner(ofTrack: "video-u9:d0") == TrackOwner(participant: 9))
        #expect(CallSdp.owner(ofTrack: "f3a1-random") == TrackOwner())
        #expect(CallSdp.layoutKey(participant: 4, screen: false) == "u4:sCAMERA")
    }

    @Test("Серверы ICE из conversationParams")
    @MainActor
    func iceFromConnection() {
        let params: JSONValue = [
            "stun": ["urls": ["stun:a:3478"]],
            "turn": ["urls": "turn:b:3478", "username": "u", "credential": "p"],
        ]
        #expect(CallSession.iceServers(from: params) == [
            CallIceServer(urls: ["stun:a:3478"]),
            CallIceServer(urls: ["turn:b:3478"], username: "u", credential: "p"),
        ])
        #expect(CallSession.iceServers(from: [:]) == nil)
        #expect(CallSession.iceServers(from: nil) == nil)
    }
}

@Suite("Каналы данных SFU")
struct SfuChannelTests {
    @Test("Раскладка видео байт в байт как у Komet")
    func layout() {
        let one = SfuChannel.displayLayout([SfuChannel.LayoutItem(trackKey: "u5:sCAMERA")], sequence: 1)
        let expected: [UInt8] = [0x00, 0x00, 0x01, 0xC3, 0x92, 0xAA] + Array("u5:sCAMERA".utf8)
            + [0x00, 0xC0, 0xCD, 0x02, 0x80, 0xCD, 0x01, 0x68, 0x00, 0xC0]
        #expect(Array(one) == expected)
        #expect(Array(SfuChannel.displayLayout([], sequence: 300)) == [0x00, 0x00, 0xCD, 0x01, 0x2C, 0xC3, 0xC0, 0xC0])
    }

    @Test("Алиасы, слоты и уровни звука")
    func notifications() throws {
        var aliasesFrame = MessagePackWriter()
        aliasesFrame.mapHeader(2)
        aliasesFrame.string("u5:sCAMERA")
        aliasesFrame.int(1)
        aliasesFrame.string("u6:sSCREEN")
        aliasesFrame.int(200)
        let aliases = try #require(SfuChannel.parse(Data([1]) + aliasesFrame.data, aliases: [:]))
        guard case .aliases(let map) = aliases else {
            Issue.record("ожидались алиасы")
            return
        }
        #expect(map == [1: "u5:sCAMERA", 200: "u6:sSCREEN"])

        var slotsFrame = MessagePackWriter()
        slotsFrame.arrayHeader(3)
        slotsFrame.int(200)
        slotsFrame.int(99)
        slotsFrame.int(1)
        #expect(SfuChannel.parse(Data([2]) + slotsFrame.data, aliases: map) == .slots(["u6:sSCREEN": 0, "u5:sCAMERA": 2]))

        var levelsFrame = MessagePackWriter()
        levelsFrame.mapHeader(1)
        levelsFrame.int(1)
        levelsFrame.int(-3)
        #expect(SfuChannel.parse(Data([6]) + levelsFrame.data, aliases: map) == .levels(["u5:sCAMERA": -3]))
        #expect(SfuChannel.parse(Data([2, 0x93, 0x01]), aliases: map) == nil)
        #expect(SfuChannel.parse(Data([9]), aliases: map) == nil)
    }

    @Test("Целые MessagePack во всех ширинах")
    func integers() throws {
        let values = [0, 127, 128, 255, 256, 65535, 65536, 4_294_967_296, -1, -32, -33, -128, -129, -40000, -3_000_000_000]
        var writer = MessagePackWriter()
        values.forEach { writer.int($0) }
        var reader = MessagePackReader(writer.data)
        for value in values {
            let read = try reader.int()
            #expect(read == value)
        }
    }
}
