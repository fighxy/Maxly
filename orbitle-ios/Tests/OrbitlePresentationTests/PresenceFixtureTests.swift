import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Общие с Kotlin сценарии строки «в сети / был(а)» из `test-fixtures/presence`.
/// Формат и правила — в README рядом с файлами.
@Suite("Статус «в сети»: общие сценарии")
struct PresenceFixtureTests {
    /// Файлы, которые проигрывает этот тест. Новый файл без строки здесь — ошибка `everyFileIsPlayed`.
    static let played = ["status", "relative", "future", "calendar"]

    @Test("Сценарии файла проигрываются", arguments: played)
    func play(_ name: String) throws {
        let fixture = try PresenceFixture.load(name)
        #expect(fixture["name"] as? String == name)
        guard let zoneId = fixture["timeZone"] as? String, let zone = TimeZone(identifier: zoneId) else {
            Issue.record("\(name): нет timeZone")
            return
        }
        guard let nowMs = (fixture["nowMs"] as? NSNumber)?.int64Value else {
            Issue.record("\(name): нет nowMs")
            return
        }
        let cases = fixture["cases"] as? [[String: Any]] ?? []
        #expect(!cases.isEmpty, "\(name): нет cases")
        let formatter = ContactsFormatter(calendar: ChatListFormatter.defaultCalendar(timeZone: zone))
        let now = Date(timeIntervalSince1970: TimeInterval(nowMs) / 1000)
        for item in cases {
            let id = item["id"] as? String ?? "?"
            let status = (item["status"] as? NSNumber)?.intValue ?? Contact.Presence.noStatus
            let seenMs = (item["seenMs"] as? NSNumber)?.int64Value ?? 0
            let presence = Contact.Presence.server(status: status, seenMs: seenMs)
            let text = formatter.status(presence, now: now)
            #expect(text == item["text"] as? String, "\(name)/\(id): строка контакта и профиля")
            let header = ChatHeaderStatus.make(kind: .user, subtitle: text, isOnline: presence == .online, live: ChatHeaderLive())
            #expect((header.text ?? "") == (item["header"] as? String), "\(name)/\(id): шапка чата")
        }
    }

    @Test("Каждый файл каталога проигрывается")
    func everyFileIsPlayed() throws {
        let files = Set(try PresenceFixture.names())
        let known = Set(Self.played)
        #expect(files.subtracting(known).isEmpty, "нет теста для файлов: \(files.subtracting(known).sorted())")
        #expect(known.subtracting(files).isEmpty, "нет файлов: \(known.subtracting(files).sorted())")
    }
}

/// Файлы сценариев ищутся от этого файла вверх до корня репозитория: SwiftPM не берёт ресурсы
/// вне каталога пакета (как у сценариев «Кем прочитано»).
enum PresenceFixture {
    static let relativePath = "test-fixtures/presence"

    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

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
        throw Missing(description: "нет каталога \(relativePath) выше \(file)")
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
            throw Missing(description: "\(name).json — не объект JSON")
        }
        return object
    }
}
