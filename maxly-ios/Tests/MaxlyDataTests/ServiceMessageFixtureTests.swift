import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

/// Сценарии служебных сообщений из `test-fixtures/service-messages`: вложение `CONTROL`
/// разбирает `MessageContentCodec`, текст строит `ServiceText`. Формат — в README рядом с ними.
@Suite("Служебные сообщения: общие сценарии")
struct ServiceMessageFixtureTests {
    static let played = ["events", "fallbacks"]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try ServiceFixture.load(name)
        #expect(fixture["kind"] as? String == "control", "\(name): kind")
        guard let cases = fixture["cases"] as? [[String: Any]], !cases.isEmpty else {
            throw FixtureError("\(name): нет случаев")
        }
        for item in cases {
            try Self.check(item, label: "\(name)/\(item["name"] as? String ?? "?")")
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        let files = Set(try ServiceFixture.names())
        let known = Set(Self.played)
        #expect(files.subtracting(known).isEmpty, "нет теста для файлов: \(files.subtracting(known).sorted())")
        #expect(known.subtracting(files).isEmpty, "нет файлов: \(known.subtracting(files).sorted())")
    }

    static func check(_ item: [String: Any], label: String) throws {
        guard let message = item["message"] as? [String: Any] else { throw FixtureError("\(label): нет message") }
        let attaches = message["attaches"] ?? []
        let data = try JSONSerialization.data(withJSONObject: ["attaches": attaches])
        let json = String(decoding: data, as: UTF8.self)
        let content = MessageContentCodec.decode(json)
        guard let expect = item["expect"] as? [String: Any] else { throw FixtureError("\(label): нет expect") }
        guard let kind = expect["kind"] as? String else {
            #expect(content.service == nil, "\(label): ждали не событие, а получили \(String(describing: content.service))")
            return
        }
        guard let parsed = content.service else { throw FixtureError("\(label): событие не разобрано") }
        #expect(content.isService, "\(label): isService")
        // Запись в базу и обратно не теряет событие.
        #expect(MessageContentCodec.decode(MessageContentCodec.encode(content)).service == parsed, "\(label): запись в базу")
        let names = (item["names"] as? [String: String]) ?? [:]
        var notice = parsed.filled(
            names: names,
            viewerId: item["viewer"] as? String ?? "",
            messageText: message["text"] as? String ?? ""
        )
        if let core = item["coreText"] as? String { notice.coreText = core }
        #expect(name(of: ServiceText.kind(notice)) == kind, "\(label): kind \(ServiceText.kind(notice))")
        let text = ServiceText.text(
            notice,
            actorId: message["sender"] as? String ?? "",
            actorName: message["senderName"] as? String ?? ""
        )
        #expect(text == expect["text"] as? String, "\(label): «\(text)»")
    }

    static func name(of kind: ServiceText.Kind) -> String {
        switch kind {
        case .joined: "joined"
        case .created: "created"
        case .added: "added"
        case .removed: "removed"
        case .left: "left"
        case .joinedByLink: "joinedByLink"
        case .renamed: "renamed"
        case .photo: "photo"
        case .botStarted: "botStarted"
        case .system: "system"
        case .unknown: "unknown"
        }
    }
}

/// Файлы `test-fixtures/service-messages`: путь ищется от этого файла вверх до корня
/// репозитория, как у сценариев звонков.
enum ServiceFixture {
    static let relativePath = "test-fixtures/service-messages"

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
        throw FixtureError("нет каталога \(relativePath) выше \(file)")
    }

    static func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory().path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    static func load(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: directory().appendingPathComponent("\(name).json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError("\(name).json — не объект JSON")
        }
        #expect(object["name"] as? String == name, "\(name): name не совпадает с файлом")
        return object
    }
}
