import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Набор текста: тексты")
struct TypingFormatterTests {
    private func people(_ names: [String?], type: String? = nil) -> [TypingFormatter.Participant] {
        names.map { TypingFormatter.Participant(name: $0, type: type) }
    }

    @Test("Тип из пуша: известные значения, всё прочее — набор текста")
    func kinds() {
        #expect(TypingKind(raw: "STICKER") == .sticker)
        #expect(TypingKind(raw: "VIDEO_MSG") == .videoMessage)
        #expect(TypingKind(raw: nil) == .text)
        #expect(TypingKind(raw: "") == .text)
        #expect(TypingKind(raw: "sticker") == .text)
        #expect(TypingKind.allCases.map(\.rawValue) == ["TEXT", "AUDIO", "VIDEO_MSG", "PHOTO", "VIDEO", "FILE", "STICKER"])
    }

    @Test("Имя без фамилии, пустое имя — неизвестно")
    func firstNames() {
        #expect(TypingFormatter.firstName("  Анна Петрова ") == "Анна")
        #expect(TypingFormatter.firstName("   ") == nil)
        #expect(TypingFormatter.firstName(nil) == nil)
        #expect(TypingFormatter.text(chatType: .group, participants: people(["Анна Петрова"])) == "Анна печатает…")
    }

    @Test("Счёт без имён склоняет существительное и глагол")
    func counts() {
        #expect(TypingFormatter.countText(2, kind: .audio) == "2 участника записывают аудио")
        #expect(TypingFormatter.countText(11, kind: .text) == "11 участников печатают")
        #expect(TypingFormatter.countText(31, kind: .sticker) == "31 участник выбирает стикер")
        #expect(ChatListFormatter.typingText(count: 2, type: .group) == "2 участника печатают…")
    }

    @Test("Имя из справочника важнее сохранённого с сообщениями")
    func namesOverride() {
        let at = Date(timeIntervalSince1970: 0)
        let activities = [TypingActivity(userId: "1", startedAt: at, name: "Анна"), TypingActivity(userId: "2", startedAt: at)]
        let participants = TypingFormatter.participants(activities, names: ["1": "Аня", "2": "Боря"])
        #expect(participants.map(\.name) == ["Аня", "Боря"])
    }

    @Test("Строка списка: имена и действие вместо превью, приватный режим их прячет")
    func listRow() {
        let formatter = ChatListFormatter()
        let typing = people(["Иван", "Петя"], type: "FILE")
        let item = formatter.item(for: chat("g", at: 1_790_000_000, type: .group), now: Date(timeIntervalSince1970: 1_790_000_000), typing: typing)
        #expect(item.previewStyle == .typing)
        #expect(item.preview == "Иван и Петя отправляют файл…")
        #expect(item.anonymousTyping == "2 участника отправляют файл…")
        #expect(item.accessibilityLabel.contains("Иван и Петя отправляют файл…"))
        #expect(PrivateModeMask.item(item).preview == "2 участника отправляют файл…")
    }
}

@Suite("Набор текста: сроки")
struct TypingTrackerTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Срок по умолчанию — 8 с, граница включительно")
    func ttl() {
        #expect(TypingTracker.defaultTTL == 8)
        var tracker = TypingTracker()
        tracker.note(chatId: "c", userId: "1", type: "TEXT", at: base)
        #expect(tracker.snapshot(at: base.addingTimeInterval(8))["c"]?.count == 1)
        #expect(tracker.snapshot(at: base.addingTimeInterval(8.001)).isEmpty)
        #expect(!tracker.isEmpty)
        let expired = tracker.expire(at: base.addingTimeInterval(8.001))
        #expect(expired)
        #expect(tracker.isEmpty)
    }

    @Test("Пустые id не учитываются, остановка без отметки ничего не меняет")
    func ignoresEmpty() {
        var tracker = TypingTracker()
        tracker.note(chatId: "", userId: "1", type: nil, at: base)
        tracker.note(chatId: "c", userId: "", type: nil, at: base)
        #expect(tracker.isEmpty)
        let stopped = tracker.stop(chatId: "c", userId: "1")
        #expect(!stopped)
    }
}

@Suite("Набор текста: отправка")
struct TypingSendPolicyTests {
    @Test("Следующий повтор записи — через 5 с от начала, после остановки повторов нет")
    func nextRepeat() {
        let clock = FixtureClock(Date(timeIntervalSince1970: 100))
        var policy = TypingSendPolicy(clock: { clock.now })
        #expect(policy.nextRepeat == nil)
        let started = policy.recordingStarted(.audio, chatId: "c")
        #expect(started == [TypingFrame(chatId: "c", type: "AUDIO")])
        #expect(policy.nextRepeat == Date(timeIntervalSince1970: 105))
        clock.now = Date(timeIntervalSince1970: 117)
        // Пропущенные шаги дают один кадр, следующий — по сетке от начала.
        let repeated = policy.tick()
        #expect(repeated == [TypingFrame(chatId: "c", type: "AUDIO")])
        #expect(policy.nextRepeat == Date(timeIntervalSince1970: 120))
        policy.recordingStopped(chatId: "c")
        #expect(policy.nextRepeat == nil)
    }

    @Test("Пустой id чата не отправляется")
    func emptyChat() {
        var policy = TypingSendPolicy()
        let frames = policy.textEdited(chatId: "")
        #expect(frames.isEmpty)
    }
}

/// Отправитель, который запоминает кадры.
private actor RecordingSender: TypingSender {
    private(set) var frames: [TypingFrame] = []

    func sendTyping(chatId: String, type: String, postId: String?) async throws {
        frames.append(TypingFrame(chatId: chatId, type: type, postId: postId))
    }
}

@Suite("Набор текста: отправитель")
@MainActor
struct TypingReporterTests {
    @Test("Кадры политики уходят в отправитель, в чужой канал — нет")
    func sends() async {
        let sender = RecordingSender()
        let reporter = TypingReporter(sender: sender)
        reporter.stickerPanelOpened(chatId: "c1")
        reporter.textEdited(chatId: "c1")
        reporter.uploadProgress(.photo, chatId: "ch", canWrite: false)
        reporter.recordingStarted(.videoMessage, chatId: "c2", postId: "p")
        reporter.recordingStopped(chatId: "c2")
        reporter.stop()
        let expected = [TypingFrame(chatId: "c1", type: "STICKER"), TypingFrame(chatId: "c2", type: "VIDEO_MSG", postId: "p")]
        #expect(await eventually { await sender.frames.count == expected.count })
        #expect(Set(await sender.frames) == Set(expected))
    }

    @Test("Заглушка ничего не делает и не бросает")
    func silent() async throws {
        try await SilentTypingSender().sendTyping(chatId: "c", type: "TEXT", postId: nil)
    }
}
