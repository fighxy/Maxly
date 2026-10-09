import Foundation
import Testing
@testable import MaxlyDomain

/// Общие с Kotlin сценарии выбора сообщений из `test-fixtures/selection`.
@Suite("Выбор сообщений: общие сценарии")
struct SelectionFixtureTests {
    static let folder = SharedFixtureFolder(folder: "selection")
    static let played = ["delete", "forward", "copy"]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try Self.folder.load(name)
        for (label, item) in try Self.folder.cases(fixture, file: name) {
            switch fixture["kind"] as? String {
            case "delete": try Self.delete(item, label)
            case "forward": try Self.forward(item, label)
            case "copy": try Self.copy(item, label)
            default: Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
            }
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        try Self.folder.checkPlayed(Self.played)
    }

    static func date(_ value: Any?, _ label: String) throws -> Date {
        Date(timeIntervalSince1970: Double(try FixtureValue.long(value, label)) / 1000)
    }

    static func delete(_ item: [String: Any], _ label: String) throws {
        let chatMap = try FixtureValue.object(item["chat"], label)
        let me = FixtureValue.string(item["me"])
        let chat = MessageSelectionRules.ChatContext(
            id: FixtureValue.string(chatMap["id"]) ?? "",
            type: ChatType.fromCore(chatMap["type"] as? String ?? ""),
            isAdmin: chatMap["admin"] as? Bool ?? false
        )
        let timeout = MessageSelectionRules.EditTimeout.server(FixtureValue.isNull(item["editTimeout"]) ? nil : try FixtureValue.int(item["editTimeout"], label))
        let now = try date(item["now"], label)
        let items = try FixtureValue.objects(item["messages"], label).map { message in
            MessageSelectionRules.Item(
                id: FixtureValue.string(message["id"]) ?? "",
                isOwn: FixtureValue.string(message["author"]) == me,
                isSent: (message["state"] as? String ?? "sent") == "sent",
                time: try date(message["time"], label)
            )
        }
        let expect = try FixtureValue.object(item["expect"], label)
        let scopes = expect["scopes"] as? [String: String] ?? [:]
        for message in items {
            let scope = MessageSelectionRules.scope(of: message, in: chat, timeout: timeout, now: now)
            #expect(scope.rawValue == scopes[message.id], "\(label): \(message.id) → \(scope)")
        }
        let options = MessageSelectionRules.deleteOptions(items, in: chat, timeout: timeout, now: now)
        #expect(options.canDelete == expect["canDelete"] as? Bool, "\(label): canDelete")
        #expect(options.showsForEveryone == expect["showsForEveryone"] as? Bool, "\(label): showsForEveryone")
        #expect(options.forEveryoneByDefault == expect["forEveryoneByDefault"] as? Bool, "\(label): forEveryoneByDefault")
        #expect(options.forcesForEveryone == expect["forcesForEveryone"] as? Bool, "\(label): forcesForEveryone")
    }

    static func forward(_ item: [String: Any], _ label: String) throws {
        let messages = try FixtureValue.objects(item["messages"], label).map { message in
            (id: FixtureValue.string(message["id"]) ?? "", time: try date(message["time"], label))
        }
        let targets = (item["targets"] as? [Any] ?? []).compactMap { FixtureValue.string($0) }
        let plan = MessageSelectionRules.forwardPlan(messages: messages, targets: targets, comment: FixtureValue.string(item["comment"]))
        let want = try FixtureValue.objects(try FixtureValue.object(item["expect"], label)["requests"], label).map { request -> MessageSelectionRules.ForwardStep in
            let target = FixtureValue.string(request["target"]) ?? ""
            if let comment = request["comment"] as? String { return .comment(target: target, text: comment) }
            return .message(target: target, messageId: FixtureValue.string(request["messageId"]) ?? "")
        }
        #expect(plan == want, "\(label): \(plan)")
    }

    static func copy(_ item: [String: Any], _ label: String) throws {
        guard let zoneId = item["timeZone"] as? String, let zone = TimeZone(identifier: zoneId) else {
            throw SharedFixtureError("\(label): нет timeZone")
        }
        let items = try FixtureValue.objects(item["messages"], label).map { message in
            MessageSelectionRules.CopyItem(
                id: FixtureValue.string(message["id"]) ?? "",
                time: try date(message["time"], label),
                authorName: message["authorName"] as? String ?? "",
                text: message["text"] as? String ?? "",
                placeholder: MessageSelectionRules.placeholder(for: media(message["media"] as? String))
            )
        }
        let got = MessageSelectionRules.copyText(items, timeZone: zone)
        #expect(got == item["expect"] as? String, "\(label): «\(got)»")
    }

    static func media(_ raw: String?) -> MessageMediaKind? {
        switch raw {
        case "PHOTO": .photo
        case "VIDEO": .video
        case "VIDEO_MESSAGE": .videoMessage
        case "VOICE": .voice
        case "FILE": .file
        case "STICKER": .sticker
        case "CONTACT": .contact
        case "POLL": .poll
        default: nil
        }
    }
}

@Suite("Выбор сообщений: удаление без конфига")
struct SelectionDeleteFallbackTests {
    @Test("Конфиг недоступен: своё отправленное удаляется у всех без срока")
    func unknownTimeout() {
        let chat = MessageSelectionRules.ChatContext(id: "5", type: .private, isAdmin: false)
        let old = MessageSelectionRules.Item(id: "1", isOwn: true, isSent: true, time: Date(timeIntervalSince1970: 0))
        #expect(MessageSelectionRules.scope(of: old, in: chat, timeout: .unknown, now: Date()) == .all)
        let foreign = MessageSelectionRules.Item(id: "2", isOwn: false, isSent: true, time: Date())
        #expect(MessageSelectionRules.scope(of: foreign, in: chat, timeout: .unknown, now: Date()) == .self)
    }
}
