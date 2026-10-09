import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Фрагмент сообщения: звонок")
struct CallContentCodecTests {
    @Test("CALL с сервера: длительность в мс, тип, исход, участники и разговор")
    func parsesServerCall() throws {
        let json = """
        {"attaches":[{"_type":"CALL","duration":125000,"hangupType":"HUNGUP","callType":"VIDEO",
        "conversationId":"9f1c","contactIds":[101,"202"]}]}
        """
        let content = MessageContentCodec.decode(json)
        let call = try #require(content.call)
        #expect(call.id == "call-9f1c")
        #expect(call.durationMs == 125_000)
        #expect(call.callType == .video)
        #expect(call.hangup == .hungup)
        #expect(call.conversationId == "9f1c")
        #expect(call.contactIds == ["101", "202"])
        #expect(!call.isGroup)
        #expect(call.isConnected)
        #expect(content.previewMedia == .call)
    }

    @Test("Пропущенный аудиозвонок без полей типа и разговора; групповой — по joinLink")
    func missedAndGroup() throws {
        let missed = try #require(MessageContentCodec.decode(#"{"attaches":[{"_type":"CALL","duration":0,"hangupType":"MISSED"}]}"#).call)
        #expect(missed.callType == .audio)
        #expect(missed.id == "call-message")
        #expect(missed.isMissed(outgoing: false))
        #expect(missed.outcome(outgoing: true) == .cancelled)

        let group = MessageContentCodec.decode(#"{"attaches":[{"_type":"CALL","duration":60000,"hangupType":"HUNGUP","joinLink":"https://call.example/j/x"}]}"#)
        #expect(group.call?.isGroup == true)
        #expect(group.previewMedia == .groupCall)
    }

    @Test("Разбор стабилен: id звонка не меняется от разбора к разбору")
    func stableId() {
        let json = #"{"attaches":[{"_type":"CALL","duration":0,"hangupType":"CANCELED"}]}"#
        #expect(MessageContentCodec.decode(json) == MessageContentCodec.decode(json))
    }

    @Test("Запись в базу и обратно без потерь, незнакомый hangupType сохраняется")
    func roundTrip() throws {
        let json = """
        {"attaches":[{"_type":"CALL","duration":3000,"hangupType":"NEW_KIND","callType":"AUDIO",
        "conversationId":"c1","contactIds":[1,2],"joinLink":"https://call.example/j/y"}],
        "reactionInfo":{"counters":[{"reaction":"👍","count":1}],"totalCount":1}}
        """
        let content = MessageContentCodec.decode(json)
        let stored = MessageContentCodec.encode(content)
        #expect(!stored.isEmpty)
        let restored = MessageContentCodec.decode(stored)
        #expect(restored == content)
        #expect(restored.call?.hangupType == "NEW_KIND")
        #expect(restored.call?.joinLink == "https://call.example/j/y")
    }

    @Test("Цитата ответа на звонок: «Звонок» или «Групповой звонок»")
    func replyPreview() throws {
        let json = """
        {"link":{"type":"REPLY","messageId":"m1","message":{"senderName":"Анна","text":"",
        "attaches":[{"_type":"CALL","duration":0,"hangupType":"MISSED"}]}}}
        """
        let reply = try #require(MessageContentCodec.decode(json).reply)
        #expect(reply.preview == "Звонок")
    }
}
