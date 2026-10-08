import Foundation
import Testing
import OrbitleDomain
@testable import OrbitleData

/// Общие с Kotlin сценарии ws2 из `test-fixtures/calls/ws2`: кадры сервера, действия приложения и
/// то, что клиент должен отправить в ответ. Формат файлов — в README рядом с ними; Kotlin
/// проигрывает те же файлы в `Ws2FixtureTest`.
///
/// Kotlin гоняет сценарий на виртуальном времени. Здесь время настоящее, поэтому каждая проверка
/// ждёт, пока условия выполнятся (`settle`), выдерживает короткую паузу и проверяет ещё раз:
/// так ловятся и лишние команды, и то, чего быть не должно (`"sent": []`, `"candidates": []`).
@Suite("Звонок: общие сценарии ws2")
@MainActor
struct CallSessionFixtureTests {
    /// Сценарии, которые проигрывает этот тест. Новый файл без строки здесь — ошибка
    /// `everyFixtureIsPlayed`, как и в Kotlin.
    nonisolated static let played = [
        "outgoing-direct", "outgoing-canceled", "outgoing-declined", "incoming-answered", "incoming-rejected",
        "incoming-missed", "ice", "errors", "conversation-closed", "screen-share-sfu",
    ]

    @Test("Сценарий ws2 проигрывается шаг за шагом", arguments: played)
    func play(_ name: String) async throws {
        let fixture = try Ws2Fixture.load(name)
        var player = try Ws2FixturePlayer(name: name, fixture: fixture)
        try await player.run()
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        let files = Set(try Ws2Fixture.names())
        let known = Set(Self.played)
        #expect(files.subtracting(known).isEmpty, "нет теста для файлов: \(files.subtracting(known).sorted())")
        #expect(known.subtracting(files).isEmpty, "нет файлов: \(known.subtracting(files).sorted())")
    }
}

/// Файлы сценариев. Ресурсом пакета их не сделать: SwiftPM не берёт файлы вне каталога пакета,
/// поэтому путь ищется от этого файла вверх до корня репозитория. Так работает и на CI
/// (`swift test --package-path orbitle-ios` из корня checkout), и локально из любого каталога.
enum Ws2Fixture {
    static let relativePath = "test-fixtures/calls/ws2"

    static func directory() throws -> URL {
        let file = #filePath
        // Каталоги от файла теста вверх: …/orbitle-ios/Tests/OrbitleDataTests, …/orbitle-ios/Tests, ….
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

    static func load(_ name: String) throws -> JSONValue {
        let url = try directory().appendingPathComponent("\(name).json")
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let value = JSONValue.parse(text), value.object != nil else {
            throw FixtureError("\(name).json — не объект JSON")
        }
        return value
    }

    /// Кадр совпадает, если совпадает каждое поле фикстуры; лишние поля кадра не важны.
    /// Числа сравниваются по значению, `null` в фикстуре — поля нет или оно `null`.
    static func matches(_ expected: JSONValue, _ actual: JSONValue?) -> Bool {
        switch expected {
        case .null:
            return actual == nil || actual == .null
        case .object(let fields):
            guard let actual, actual.object != nil else { return false }
            return fields.allSatisfy { key, value in matches(value, actual[key]) }
        case .array(let items):
            guard let list = actual?.array, list.count == items.count else { return false }
            return zip(items, list).allSatisfy { matches($0, $1) }
        case .string(let text):
            return actual?.string == text
        case .bool(let flag):
            return actual?.bool == flag
        case .int, .double:
            guard let actual, actual.string == nil, let value = actual.double else { return false }
            return value == expected.double
        }
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Проигрывает один сценарий против `CallSession` с фейковыми сервером и медиа.
@MainActor
struct Ws2FixturePlayer {
    /// Сколько ждать, пока проверка выполнится.
    private static let timeout: Duration = .seconds(3)
    /// Тишина после выполненной проверки: за неё успели бы уйти лишние команды.
    private static let quiet: Duration = .milliseconds(30)

    private let name: String
    private let steps: [JSONValue]
    private let server = FakeWs2Server()
    private let media = FakeCallMedia()
    private let call: CallSession
    private var seenFrames = 0
    private var seenTexts = 0
    private var stepIndex = 0

    init(name: String, fixture: JSONValue) throws {
        self.name = name
        guard let steps = fixture["steps"]?.array else { throw FixtureError("\(name): нет steps") }
        self.steps = steps
        guard let rawRole = fixture["role"]?.string, let role = CallRole(rawValue: rawRole.lowercased()) else {
            throw FixtureError("\(name): неизвестная роль \(fixture["role"]?.serialized() ?? "nil")")
        }
        let url = fixture["signalingUrl"]?.string ?? "wss://sig.test/ws"
        guard let signalingURL = URL(string: url) else { throw FixtureError("\(name): плохой signalingUrl \(url)") }
        let connection = CallConnection(
            conversationId: fixture["conversationId"]?.string ?? "conv",
            signalingURL: signalingURL,
            selfId: fixture["selfId"]?.int ?? 10
        )
        // Те же задержки, что в CallSessionTests и Ws2FixtureTest: сервер не будят, ICE не ждут.
        var timing = CallSession.Timing()
        timing.wake = .seconds(60)
        timing.gathering = .milliseconds(20)
        timing.reconnect = [.milliseconds(5), .milliseconds(5)]
        timing.levels = .seconds(60)
        call = CallSession(
            connection: connection, role: role, isGroup: fixture["isGroup"]?.bool == true, media: media,
            connector: FakeConnector([server]).connector, timing: timing
        )
    }

    mutating func run() async throws {
        for step in steps {
            stepIndex += 1
            if let action = step["do"] {
                switch action.string {
                case "start": await call.start()
                case "accept": await call.accept(video: step["video"]?.bool == true)
                case "hangUp": await call.hangUp()
                case "setCamera":
                    let on = try flag(step)
                    await call.setCamera(on)
                case "setScreenSharing":
                    let on = try flag(step)
                    await call.setScreenSharing(on)
                default: throw FixtureError(at("неизвестное действие \(action.serialized())"))
                }
            } else if let frame = step["receive"] {
                server.deliver(frame)
            } else if let text = step["receiveText"] {
                guard let text = text.string else { throw FixtureError(at("receiveText — не строка")) }
                server.deliver(text: text)
            } else if let event = step["peerEvent"] {
                try await peerEvent(event)
            } else if let answer = step["peerAnswer"] {
                try await peerAnswer(answer)
            } else if let expect = step["expect"] {
                await check(expect)
            } else {
                throw FixtureError(at("неизвестный шаг \(step.serialized())"))
            }
        }
    }

    // MARK: Шаги

    /// `"on": true/false` действий `setCamera` и `setScreenSharing`.
    private func flag(_ step: JSONValue) throws -> Bool {
        guard let on = step["on"]?.bool else { throw FixtureError(at("действие без \"on\"")) }
        return on
    }

    /// Свой SDP, которым фейковый WebRTC ответит на следующие оферы.
    private func peerAnswer(_ answer: JSONValue) async throws {
        guard let sdp = answer.string else { throw FixtureError(at("peerAnswer — не строка")) }
        _ = await settle(timeout: Self.timeout) { media.peer != nil }
        guard let peer = media.peer else { throw FixtureError(at("peerAnswer без соединения")) }
        peer.answerSdp = sdp
    }

    private func peerEvent(_ event: JSONValue) async throws {
        _ = await settle(timeout: Self.timeout) { media.peer != nil }
        guard let peer = media.peer else { throw FixtureError(at("событие WebRTC без соединения")) }
        if let candidate = event["candidate"] {
            guard let sdp = candidate["sdp"]?.string else { throw FixtureError(at("кандидат без sdp")) }
            let index = Int32(truncatingIfNeeded: candidate["sdpMLineIndex"]?.int ?? 0)
            peer.emit(.candidate(IceCandidate(sdp: sdp, sdpMid: candidate["sdpMid"]?.string, sdpMLineIndex: index)))
        }
        if let raw = event["state"]?.string {
            guard let state = Self.peerState(raw) else { throw FixtureError(at("неизвестное состояние WebRTC \(raw)")) }
            peer.emit(.state(state))
        }
    }

    /// Ждёт, пока все условия выполнятся, выдерживает тишину и проверяет каждое уже с сообщением.
    private mutating func check(_ expect: JSONValue) async {
        _ = await settle(timeout: Self.timeout) { failures(expect).isEmpty }
        try? await Task.sleep(for: Self.quiet)
        for failure in failures(expect) {
            Issue.record(Comment(rawValue: at(failure)))
        }
        if expect["sent"] != nil { seenFrames = server.frames.count }
        if expect["sentTexts"] != nil { seenTexts = server.texts.count }
    }

    /// Что из `expect` сейчас не выполнено; пусто — всё совпало.
    private func failures(_ expect: JSONValue) -> [String] {
        var problems: [String] = []
        let state = call.state
        if let phase = expect["phase"]?.string, Self.name(of: state.phase) != phase {
            problems.append("фаза: ждали \(phase), сейчас \(Self.name(of: state.phase))")
        }
        if let ended = expect["ended"]?.string {
            let actual = Self.endReason(state.phase)
            if actual != ended { problems.append("причина конца: ждали \(ended), сейчас \(actual ?? "нет")") }
        }
        if let connected = expect["mediaConnected"]?.bool, state.mediaConnected != connected {
            problems.append("mediaConnected: ждали \(connected), сейчас \(state.mediaConnected)")
        }
        if let closed = expect["socketClosed"]?.bool, server.isClosed != closed {
            problems.append("сокет закрыт: ждали \(closed), сейчас \(server.isClosed)")
        }
        if let sent = expect["sent"] {
            let fresh = server.frames.dropFirst(seenFrames).filter { $0["command"] != nil }
            let wanted = sent.array ?? []
            let names = fresh.map { $0["command"]?.string ?? "?" }
            if wanted.count != fresh.count {
                problems.append("команды: ждали \(wanted.count), ушли \(names)")
            } else {
                for (index, (frame, actual)) in zip(wanted, fresh).enumerated() where !Ws2Fixture.matches(frame, actual) {
                    problems.append("команда \(index + 1): ждали \(frame.serialized()), ушло \(actual.serialized())")
                }
            }
        }
        if let texts = expect["sentTexts"] {
            let fresh = server.texts.dropFirst(seenTexts).filter { JSONValue.parse($0)?.object == nil }
            let wanted = (texts.array ?? []).compactMap(\.string)
            if Array(fresh) != wanted { problems.append("текстовые кадры: ждали \(wanted), ушли \(Array(fresh))") }
        }
        if let labels = expect["sdpLabels"]?.array {
            let wanted = labels.compactMap(\.string)
            let actual = Self.labels(in: lastSentSdp())
            if wanted != actual { problems.append("подписи своего SDP: ждали \(wanted), ушли \(actual)") }
        }
        if let peer = expect["peer"] {
            problems += peerFailures(peer)
        }
        return problems
    }

    /// SDP последней команды клиента, которая его несёт: `accept-producer` или `transmit-data`.
    private func lastSentSdp() -> String {
        for frame in server.frames.reversed() {
            switch frame["command"]?.string {
            case "accept-producer":
                if let sdp = frame["description"]?.string { return sdp }
            case "transmit-data":
                if let sdp = frame["data"]?["sdp"]?["sdp"]?.string { return sdp }
            default:
                break
            }
        }
        return ""
    }

    /// Подписи своего видео `u<id>:s<ВИД>` в SDP по порядку, без повторов.
    private static func labels(in sdp: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: "u[0-9]+:s[A-Z]+") else { return [] }
        let text = sdp as NSString
        var result: [String] = []
        for match in pattern.matches(in: sdp, range: NSRange(location: 0, length: text.length)) {
            let label = text.substring(with: match.range)
            if !result.contains(label) { result.append(label) }
        }
        return result
    }

    private func peerFailures(_ expected: JSONValue) -> [String] {
        if expected == .null {
            return media.peer == nil ? [] : ["соединения WebRTC ещё быть не должно"]
        }
        guard let peer = media.peer else { return ["нет соединения WebRTC"] }
        var problems: [String] = []
        if let microphone = expected["microphone"]?.bool, peer.microphone != microphone {
            problems.append("микрофон: ждали \(microphone), сейчас \(peer.microphone)")
        }
        if let count = expected["iceServers"]?.int, peer.iceServers.count != Int(count) {
            problems.append("ICE-серверы: ждали \(count), сейчас \(peer.iceServers.count)")
        }
        if let remotes = expected["remotes"]?.array {
            let wanted = remotes.compactMap(\.string)
            let actual = peer.remotes.map(\.type.rawValue)
            if wanted != actual { problems.append("удалённые SDP: ждали \(wanted), сейчас \(actual)") }
        }
        if let videos = expected["sendVideo"]?.array {
            let wanted = videos.compactMap(\.string)
            let actual = peer.sending.map(\.rawValue)
            if wanted != actual { problems.append("sendVideo: ждали \(wanted), было \(actual)") }
        }
        if let slot = expected["slot"] {
            let actual = peer.slotVideo?.rawValue
            if slot.string != actual { problems.append("слот SFU: ждали \(slot.string ?? "пусто"), сейчас \(actual ?? "пусто")") }
        }
        if let candidates = expected["candidates"]?.array {
            let actual: [JSONValue] = peer.candidates.map {
                [
                    "sdp": .string($0.sdp),
                    "sdpMid": $0.sdpMid.map(JSONValue.string) ?? .null,
                    "sdpMLineIndex": .int(Int64($0.sdpMLineIndex)),
                ]
            }
            let shown = actual.map { $0.serialized() }
            if candidates.count != actual.count {
                problems.append("кандидаты собеседника: ждали \(candidates.count), сейчас \(shown)")
            } else {
                for (index, (candidate, have)) in zip(candidates, actual).enumerated() where !Ws2Fixture.matches(candidate, have) {
                    problems.append("кандидат \(index + 1): ждали \(candidate.serialized()), есть \(have.serialized())")
                }
            }
        }
        return problems
    }

    private func at(_ what: String) -> String {
        "\(name), шаг \(stepIndex): \(what)"
    }

    // MARK: Имена из фикстур

    /// Имена фаз и причин — как классы Kotlin, их пишут фикстуры.
    private static func name(of phase: CallState.Phase) -> String {
        switch phase {
        case .connecting: "Connecting"
        case .ringing: "Ringing"
        case .active: "Active"
        case .reconnecting: "Reconnecting"
        case .ended: "Ended"
        }
    }

    private static func endReason(_ phase: CallState.Phase) -> String? {
        guard case .ended(let reason) = phase else { return nil }
        switch reason {
        case .hungUp: return "HungUp"
        case .remoteHungUp: return "RemoteHungUp"
        case .declined: return "Declined"
        case .busy: return "Busy"
        case .noAnswer: return "NoAnswer"
        case .rejected: return "Rejected"
        case .missed: return "Missed"
        case .connectionLost: return "ConnectionLost"
        case .failed: return "Failed"
        }
    }

    private static func peerState(_ raw: String) -> PeerState? {
        switch raw.uppercased() {
        case "NEW": .new
        case "CONNECTING": .connecting
        case "CONNECTED": .connected
        case "DISCONNECTED": .disconnected
        case "FAILED": .failed
        case "CLOSED": .closed
        default: nil
        }
    }
}
