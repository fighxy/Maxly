import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Prefetch картинок по окну скролла")
struct TranscriptImagePrefetchTests {
    @Test("К новым берёт хвост видимого окна, к истории — голову")
    func directionShiftsWindow() {
        let messages = (0..<30).map { message(id: "m\($0)") }
        let towardNew = TranscriptImagePrefetch.plan(
            messages: messages, visibleRange: 10..<15, scrollingTowardOlder: false, window: 5
        )
        let towardOld = TranscriptImagePrefetch.plan(
            messages: messages, visibleRange: 10..<15, scrollingTowardOlder: true, window: 5
        )
        let newSet = Set(towardNew.urls)
        let oldSet = Set(towardOld.urls)
        let expectedNew = Set(TranscriptImagePrefetch.urls(in: messages[10..<20]))
        let expectedOld = Set(TranscriptImagePrefetch.urls(in: messages[5..<15]))
        #expect(newSet == expectedNew)
        #expect(oldSet == expectedOld)
    }

    @Test("Без видимого диапазона — последние window сообщений")
    func defaultTail() {
        let messages = (0..<40).map { message(id: "m\($0)") }
        let plan = TranscriptImagePrefetch.plan(
            messages: messages, visibleRange: nil, scrollingTowardOlder: false, window: 10
        )
        #expect(Set(plan.urls) == Set(TranscriptImagePrefetch.urls(in: messages[30..<40])))
    }

    private func message(id: String) -> Message {
        Message(
            id: id,
            chatId: "c",
            authorId: "u",
            text: id,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            status: .sent,
            authorAvatarURL: URL(string: "https://example.invalid/\(id).png")
        )
    }
}
