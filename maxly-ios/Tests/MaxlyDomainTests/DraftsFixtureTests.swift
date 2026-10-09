import Foundation
import Testing
@testable import MaxlyDomain

/// Общие с Kotlin сценарии черновиков на сервере из `test-fixtures/drafts`.
@Suite("Черновики: общие сценарии")
struct DraftsFixtureTests {
    static let folder = SharedFixtureFolder(folder: "drafts")
    static let played = ["merge", "outgoing"]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try Self.folder.load(name)
        for (label, item) in try Self.folder.cases(fixture, file: name) {
            switch fixture["kind"] as? String {
            case "merge": try Self.merge(item, label)
            case "outgoing": try Self.outgoing(item, label)
            default: Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
            }
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        try Self.folder.checkPlayed(Self.played)
    }

    static func draft(_ value: Any?, _ label: String) throws -> SyncedDraft? {
        if FixtureValue.isNull(value) { return nil }
        let map = try FixtureValue.object(value, label)
        return SyncedDraft(
            text: map["text"] as? String ?? "",
            spans: try FixtureValue.spans(map["spans"], label),
            replyTo: FixtureValue.string(map["replyTo"]),
            updateTime: try FixtureValue.long(map["updateTime"], label)
        )
    }

    static func merge(_ item: [String: Any], _ label: String) throws {
        let discarded = FixtureValue.isNull(item["discardedAt"]) ? nil : try FixtureValue.long(item["discardedAt"], label)
        let got = DraftSync.merge(local: try draft(item["local"], label), server: try draft(item["server"], label), discardedAt: discarded)
        #expect(got == (try draft(item["expect"], label)), "\(label): \(String(describing: got))")
    }

    static func outgoing(_ item: [String: Any], _ label: String) throws {
        let chat = try FixtureValue.object(item["chat"], label)
        let me = FixtureValue.string(item["me"]) ?? ""
        let type = ChatType.fromCore(chat["type"] as? String ?? "")
        guard let address = DraftSync.address(chatId: FixtureValue.string(chat["id"]) ?? "", type: type,
                                              peerId: FixtureValue.string(chat["peerId"]), me: me) else {
            throw SharedFixtureError("\(label): нет адреса")
        }
        let request = DraftSync.request(local: try draft(item["local"], label), server: try draft(item["server"], label), address: address)
        let expect = try FixtureValue.object(item["expect"], label)
        let wantName = FixtureValue.string(expect["request"])
        switch request {
        case nil:
            #expect(wantName == nil, "\(label): запроса нет, а ждали \(String(describing: wantName))")
        case let .save(address, text, elements, replyTo)?:
            #expect(wantName == "DRAFT_SAVE", "\(label): DRAFT_SAVE")
            let payload = try FixtureValue.object(expect["payload"], label)
            #expect(FixtureValue.string(payload[address.key]) == address.id, "\(label): адрес \(address.key)")
            let draft = try FixtureValue.object(payload["draft"], label)
            #expect(draft["text"] as? String == (text.isEmpty ? nil : text), "\(label): текст")
            // Пустой текст не отправляется: ключа нет ни в сценарии, ни в теле запроса.
            let body = request?.payload["draft"] as? [String: Any] ?? [:]
            #expect(Set(body.keys) == Set(draft.keys), "\(label): ключи \(body.keys.sorted())")
            #expect((try FixtureValue.elements(draft["elements"], label)) == elements, "\(label): \(elements)")
            #expect(FixtureValue.string(draft["replyTo"]) == replyTo, "\(label): replyTo")
        case let .discard(address, time)?:
            #expect(wantName == "DRAFT_DISCARD", "\(label): DRAFT_DISCARD")
            let payload = try FixtureValue.object(expect["payload"], label)
            #expect(FixtureValue.string(payload[address.key]) == address.id, "\(label): адрес \(address.key)")
            #expect((try FixtureValue.long(payload["time"], label)) == time, "\(label): time")
        }
    }
}
