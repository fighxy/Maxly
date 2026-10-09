import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Общие с Kotlin сценарии «печатает…» из `test-fixtures/typing`: тексты, сроки отметок и
/// отправка своего кадра 65. Формат файлов — в README рядом с ними.
@Suite("Набор текста: общие сценарии")
struct TypingFixtureTests {
    /// Сценарии, которые проигрывает этот тест. Новый файл без строки здесь — ошибка
    /// `everyFixtureIsPlayed`.
    static let played = [
        "texts-private", "texts-group", "texts-names-unknown", "texts-channel",
        "expiry-ttl", "expiry-order", "expiry-message",
        "sending-text", "sending-throttle-per-chat", "sending-type-change", "sending-recording", "sending-uploads",
        "sending-sticker", "sending-channel",
    ]

    @Test("Сценарий проигрывается шаг за шагом", arguments: played)
    func play(_ name: String) throws {
        let fixture = try TypingFixture.load(name)
        #expect(fixture["name"] as? String == name)
        switch fixture["kind"] as? String {
        case "texts": try TypingFixturePlayer.texts(fixture, file: name)
        case "expiry": try TypingFixturePlayer.expiry(fixture, file: name)
        case "sending": try TypingFixturePlayer.sending(fixture, file: name)
        default: Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        let files = Set(try TypingFixture.names())
        let known = Set(Self.played)
        #expect(files.subtracting(known).isEmpty, "нет теста для файлов: \(files.subtracting(known).sorted())")
        #expect(known.subtracting(files).isEmpty, "нет файлов: \(known.subtracting(files).sorted())")
    }
}

struct TypingFixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Файлы сценариев. Ресурсом пакета их не сделать: SwiftPM не берёт файлы вне каталога пакета,
/// поэтому путь ищется от этого файла вверх до корня репозитория (как у сценариев звонков).
enum TypingFixture {
    static let relativePath = "test-fixtures/typing"

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
        throw TypingFixtureError("нет каталога \(relativePath) выше \(file)")
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
            throw TypingFixtureError("\(name).json — не объект JSON")
        }
        return object
    }
}

/// Проигрыватель трёх видов сценариев.
enum TypingFixturePlayer {
    /// Начало отсчёта сценария: время шага — `base + at`.
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static func date(_ ms: Int) -> Date {
        base.addingTimeInterval(TimeInterval(ms) / 1000)
    }

    /// Строка или `nil` для `null` и отсутствующего поля.
    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func int(_ value: Any?, _ context: String) throws -> Int {
        if let number = value as? Int { return number }
        guard let number = value as? NSNumber else { throw TypingFixtureError("\(context): нет числа") }
        return number.intValue
    }

    static func objects(_ value: Any?, _ context: String) throws -> [[String: Any]] {
        guard let list = value as? [[String: Any]] else { throw TypingFixtureError("\(context): нет списка объектов") }
        return list
    }

    // MARK: Тексты

    static func texts(_ fixture: [String: Any], file: String) throws {
        let cases = try objects(fixture["cases"], file)
        #expect(!cases.isEmpty, "\(file): нет случаев")
        for item in cases {
            let label = "\(file)/\(string(item["name"]) ?? "?")"
            let chatType = try chatType(item["chat"], label)
            var activities: [TypingActivity] = []
            for user in try objects(item["typing"], label) {
                let started = try int(user["startedAt"], label)
                activities.append(TypingActivity(
                    userId: string(user["userId"]) ?? "",
                    type: string(user["type"]),
                    startedAt: date(started),
                    name: string(user["name"])
                ))
            }
            let participants = TypingFormatter.participants(TypingTracker.ordered(activities))
            let list = string(item["list"])
            let header = string(item["header"])

            #expect(TypingFormatter.text(chatType: chatType, participants: participants) == list, "\(label): строка")
            #expect(TypingFormatter.headerText(chatType: chatType, participants: participants) == header, "\(label): шапка")

            // Та же строка в списке чатов: вместо превью, если кто-то печатает.
            let row = ChatListFormatter().item(for: chat("c", at: 1_790_000_000, type: chatType), now: base, typing: participants)
            if let list {
                #expect(row.previewStyle == .typing && row.preview == list, "\(label): строка списка — \(row.preview)")
            } else {
                #expect(row.previewStyle != .typing, "\(label): в строке списка не должно быть индикатора")
            }

            // И в шапке чата.
            let kind: ChatProfile.Kind = switch chatType {
            case .private: .user
            case .group: .group
            case .channel: .channel
            }
            let status = ChatHeaderStatus.make(kind: kind, subtitle: "Был(а) недавно", isOnline: false, live: ChatHeaderLive(typing: participants))
            if case .typing(let text) = status {
                #expect(text == header, "\(label): шапка чата — \(text)")
            } else {
                #expect(header == nil, "\(label): в шапке нет индикатора, ожидалось «\(header ?? "")»")
            }
        }
    }

    static func chatType(_ value: Any?, _ context: String) throws -> ChatType {
        switch string(value) {
        case "private": .private
        case "group": .group
        case "channel": .channel
        default: throw TypingFixtureError("\(context): неизвестный chat")
        }
    }

    // MARK: Сроки

    static func expiry(_ fixture: [String: Any], file: String) throws {
        let ttl = try int(fixture["ttlMs"], file)
        #expect(ttl == Int(TypingTracker.defaultTTL * 1000), "\(file): срок отметки приложения")
        var tracker = TypingTracker(ttl: TimeInterval(ttl) / 1000)
        var checks = 0
        for (index, step) in try objects(fixture["steps"], file).enumerated() {
            let label = "\(file)#\(index)"
            let at = date(try int(step["at"], label))
            if let push = step["push"] as? [String: Any] {
                tracker.note(chatId: string(push["chatId"]) ?? "", userId: string(push["userId"]) ?? "", type: string(push["type"]), at: at)
            } else if let message = step["message"] as? [String: Any] {
                tracker.stop(chatId: string(message["chatId"]) ?? "", userId: string(message["userId"]) ?? "")
            } else if let expected = step["expect"] as? [String: Any] {
                checks += 1
                tracker.expire(at: at)
                let actual = tracker.snapshot(at: at).mapValues { list in list.map { Pair(userId: $0.userId, type: $0.type) } }
                var wanted: [String: [Pair]] = [:]
                for (chatId, users) in expected {
                    wanted[chatId] = try objects(users, label).map { Pair(userId: string($0["userId"]) ?? "", type: string($0["type"])) }
                }
                #expect(actual == wanted, "\(label): печатают \(actual), ожидалось \(wanted)")
            } else {
                throw TypingFixtureError("\(label): неизвестный шаг")
            }
        }
        #expect(checks > 0, "\(file): нет проверок")
    }

    struct Pair: Equatable, CustomStringConvertible {
        let userId: String
        let type: String?
        var description: String { "\(userId):\(type ?? "null")" }
    }

    // MARK: Отправка

    static func sending(_ fixture: [String: Any], file: String) throws {
        let clock = FixtureClock(base)
        var policy = TypingSendPolicy(clock: { clock.now })
        for (index, step) in try objects(fixture["steps"], file).enumerated() {
            let label = "\(file)#\(index)"
            clock.now = date(try int(step["at"], label))
            let chatId = string(step["chatId"]) ?? ""
            let postId = string(step["postId"])
            let canWrite = (step["canWrite"] as? Bool) ?? true
            let kind = TypingKind(raw: string(step["type"]))
            let frames: [TypingFrame]
            switch string(step["do"]) {
            case "editText": frames = policy.textEdited(chatId: chatId, postId: postId, canWrite: canWrite)
            case "startRecording": frames = policy.recordingStarted(kind, chatId: chatId, postId: postId, canWrite: canWrite)
            case "stopRecording":
                policy.recordingStopped(chatId: chatId)
                frames = []
            case "uploadProgress": frames = policy.uploadProgress(kind, chatId: chatId, postId: postId, canWrite: canWrite)
            case "openStickers": frames = policy.stickerPanelOpened(chatId: chatId, postId: postId, canWrite: canWrite)
            case "tick": frames = policy.tick()
            default: throw TypingFixtureError("\(label): неизвестное действие \(String(describing: step["do"]))")
            }
            let expected = try objects(step["sent"], label).map {
                TypingFrame(chatId: string($0["chatId"]) ?? "", type: string($0["type"]) ?? "", postId: string($0["postId"]))
            }
            #expect(frames == expected, "\(label): отправлено \(frames), ожидалось \(expected)")
        }
    }
}

/// Часы сценария: время двигает проигрыватель.
final class FixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date) { value = start }

    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
