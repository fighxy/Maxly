import Foundation
import Testing
@testable import OrbitleDomain

/// Общие с Kotlin сценарии «Кем прочитано» и строки прочтения из `test-fixtures/readers`.
/// Формат файлов и правила — в README рядом с ними.
@Suite("Кем прочитано: общие сценарии")
struct ReadersFixtureTests {
    /// Сценарии, которые проигрывает этот тест. Новый файл без строки здесь — ошибка
    /// `everyFixtureIsPlayed`.
    static let played = [
        "reactors-first", "read-and-reacted-once", "mark-equals-time", "exclude-self", "exclude-author",
        "own-message", "incoming-message",
        "not-private", "not-saved-messages", "not-channel", "not-video-conversation",
        "message-sending", "message-failed", "message-scheduled",
        "group-size-100", "group-size-101", "group-size-server-lower", "group-size-server-higher",
        "pushed-mark-newer", "pushed-mark-older", "live-push",
        "reactor-not-participant", "reactions-error", "nobody", "readers-order-ties", "ids-string-and-number",
        "info-private-status",
    ]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try ReadersFixture.load(name)
        #expect(fixture["name"] as? String == name)
        switch fixture["kind"] as? String {
        case "readers": try ReadersFixturePlayer.readers(fixture, file: name)
        case "info": try ReadersFixturePlayer.info(fixture, file: name)
        default: Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        let files = Set(try ReadersFixture.names())
        let known = Set(Self.played)
        #expect(files.subtracting(known).isEmpty, "нет теста для файлов: \(files.subtracting(known).sorted())")
        #expect(known.subtracting(files).isEmpty, "нет файлов: \(known.subtracting(files).sorted())")
    }
}

struct ReadersFixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Файлы сценариев. Ресурсом пакета их не сделать: SwiftPM не берёт файлы вне каталога пакета,
/// поэтому путь ищется от этого файла вверх до корня репозитория (как у сценариев набора текста).
enum ReadersFixture {
    static let relativePath = "test-fixtures/readers"

    static func directory() throws -> URL {
        let file = #filePath
        var components = URL(fileURLWithPath: file).deletingLastPathComponent().pathComponents
        while !components.isEmpty {
            let candidate = URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
                .appendingPathComponent(relativePath, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            components.removeLast()
        }
        throw ReadersFixtureError("нет каталога \(relativePath) выше \(file)")
    }

    static func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory().path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    static func load(_ name: String) throws -> [String: Any] {
        let url = try directory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadersFixtureError("\(name).json — не объект JSON")
        }
        return object
    }
}

/// Проигрыватель двух видов сценариев.
enum ReadersFixturePlayer {
    static func object(_ value: Any?, _ context: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw ReadersFixtureError("\(context): нет объекта") }
        return object
    }

    static func objects(_ value: Any?, _ context: String) throws -> [[String: Any]] {
        guard let list = value as? [[String: Any]] else { throw ReadersFixtureError("\(context): нет списка объектов") }
        return list
    }

    static func int(_ value: Any?, _ context: String) throws -> Int64 {
        guard let number = MessageReaders.number(value) else { throw ReadersFixtureError("\(context): нет числа") }
        return number
    }

    static func state(_ value: Any?, _ context: String) throws -> MessageReaders.MessageState {
        guard let raw = value as? String, let state = MessageReaders.MessageState(rawValue: raw) else {
            throw ReadersFixtureError("\(context): неизвестное state \(String(describing: value))")
        }
        return state
    }

    /// Пуши в виде `{"id": отметка}`: значения числа или строки, как в `participants`.
    static func pushed(_ value: Any?) -> [String: Int64] {
        MessageReaders.marks(participants: value as? [String: Any])
    }

    static func readers(_ value: Any?, _ context: String) throws -> [MessageReader] {
        try objects(value, context).map { entry in
            guard let id = entry["userId"] as? String else { throw ReadersFixtureError("\(context): userId не строка") }
            return MessageReader(userId: id, reaction: entry["reaction"] as? String)
        }
    }

    // MARK: readers

    static func readers(_ fixture: [String: Any], file: String) throws {
        let chat = try object(fixture["chat"], "\(file)/chat")
        let message = try object(fixture["message"], "\(file)/message")
        let me = MessageReaders.userId(fixture["me"])
        let author = MessageReaders.userId(message["author"])
        let time = try int(message["time"], "\(file)/message.time")

        let available = MessageReaders.isAvailable(
            chatId: chat["id"] as? String ?? "",
            chatType: chat["type"] as? String ?? "",
            isVideoConversation: chat["videoConversation"] as? Bool ?? false,
            participantsCount: Int(try int(chat["participantsCount"], "\(file)/participantsCount")),
            messageState: try state(message["state"], file),
            maxReadmarks: MessageReaders.maxReadmarks(server: (fixture["serverMaxReadmarks"] as? NSNumber)?.intValue)
        )

        let reactions: [MessageReaders.Reaction]? = (fixture["reactionsError"] as? Bool == true) ? nil :
            try objects(fixture["reactions"] ?? [[String: Any]](), "\(file)/reactions").map { entry in
                MessageReaders.Reaction(
                    userId: MessageReaders.userId(entry["userId"]) ?? "",
                    emoji: entry["reaction"] as? String ?? ""
                )
            }

        var marks = MessageReaders.marks(
            participants: chat["participants"] as? [String: Any],
            pushed: pushed(fixture["pushedMarks"])
        )

        func check(_ expect: [String: Any], _ label: String) throws {
            let wantAvailable = expect["available"] as? Bool
            #expect(available == wantAvailable, "\(label): available")
            let list = available
                ? MessageReaders.build(messageTime: time, authorId: author, me: me, marks: marks, reactions: reactions)
                : []
            let want = try readers(expect["readers"], label)
            #expect(list == want, "\(label): список \(list)")
        }

        try check(try object(fixture["expect"], "\(file)/expect"), file)
        for (index, step) in try objects(fixture["steps"] ?? [[String: Any]](), "\(file)/steps").enumerated() {
            let label = "\(file)/step \(index + 1)"
            let push = try object(step["push"], label)
            guard let user = MessageReaders.userId(push["userId"]) else { throw ReadersFixtureError("\(label): нет userId") }
            marks = MessageReaders.merged(marks, [user: try int(push["mark"], label)])
            try check(try object(step["expect"], label), label)
        }
    }

    // MARK: info

    static func info(_ fixture: [String: Any], file: String) throws {
        let cases = try objects(fixture["cases"], file)
        #expect(!cases.isEmpty, "\(file): нет случаев")
        for item in cases {
            let label = "\(file)/\(item["name"] as? String ?? "?")"
            let chat = try object(item["chat"], label)
            let expect = try object(item["expect"], label)
            let status = MessageReaders.privateStatus(
                chatId: chat["id"] as? String ?? "",
                chatType: chat["type"] as? String ?? "",
                isOwn: item["own"] as? Bool ?? false,
                messageState: try state(item["state"], label),
                messageTime: try int(item["messageTime"], label),
                peerMark: try int(item["peerMark"], label)
            )
            #expect(status?.rawValue == expect["status"] as? String, "\(label): статус \(String(describing: status))")
            #expect(status?.title == expect["text"] as? String, "\(label): текст")
        }
    }
}

/// Правила, которые сценарии не проверяют отдельно.
@Suite("Кем прочитано: разбор")
struct MessageReadersParsingTests {
    @Test("Порог: нет значения или не больше нуля — 100")
    func threshold() {
        #expect(MessageReaders.maxReadmarks(server: nil) == 100)
        #expect(MessageReaders.maxReadmarks(server: 0) == 100)
        #expect(MessageReaders.maxReadmarks(server: -5) == 100)
        #expect(MessageReaders.maxReadmarks(server: 30) == 30)
    }

    @Test("Ключи participants бывают числами, true/false и дробные — не id")
    func numericKeys() {
        let raw: [AnyHashable: Any] = [5: 7000, "6": "8000", 7: true, "8": 1.5, 9: NSNumber(value: 6000)]
        #expect(MessageReaders.marks(participants: raw) == ["5": 7000, "6": 8000, "9": 6000])
    }
}
