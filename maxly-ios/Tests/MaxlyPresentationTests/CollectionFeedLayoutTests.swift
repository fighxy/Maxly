import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Раскладка высот ленты")
struct CollectionFeedLayoutTests {
    @Test("Соседние строки не делят одну высоту")
    func perRowHeights() {
        let short = row(text: "hi")
        let long = row(text: String(repeating: "слово ", count: 40))
        let rows = [short, long]
        let cache = BubbleHeightCache()
        let newest = CollectionFeedLayout.height(displayIndex: 0, chronological: rows, maxWidth: 280, cache: cache)
        let older = CollectionFeedLayout.height(displayIndex: 1, chronological: rows, maxWidth: 280, cache: cache)
        #expect(newest != nil)
        #expect(older != nil)
        #expect(newest! > older!)
    }

    @Test("Записанная высота не подменяет соседа")
    func storedHeightStaysOnItsRow() {
        let short = row(text: "hi")
        let long = row(text: String(repeating: "слово ", count: 20))
        let rows = [short, long]
        let cache = BubbleHeightCache()
        cache.store(id: short.id, height: 400)
        let newest = CollectionFeedLayout.height(displayIndex: 0, chronological: rows, maxWidth: 280, cache: cache)
        let older = CollectionFeedLayout.height(displayIndex: 1, chronological: rows, maxWidth: 280, cache: cache)
        #expect(older == 400)
        #expect(newest != 400)
    }

    @Test("Бегунок: низ при offset 0, верх в конце истории, скрыт без переполнения")
    func thumbTracksInvertedOffset() {
        let bottom = InvertedThumbFrame.make(offset: 0, content: 1000, viewport: 200, track: 200)
        #expect(!bottom.hidden)
        #expect(abs((bottom.y + bottom.height) - 200) < 0.01)
        let top = InvertedThumbFrame.make(offset: 800, content: 1000, viewport: 200, track: 200)
        #expect(top.y == 0)
        let idle = InvertedThumbFrame.make(offset: 0, content: 100, viewport: 200, track: 200)
        #expect(idle.hidden)
    }

    @Test("VoiceOver читает сверху вниз: старое и шапка раньше новых")
    func accessibilityTopToBottom() {
        let paths = [
            FeedIndexPath(section: 1, item: 0),
            FeedIndexPath(section: 1, item: 2),
            FeedIndexPath(section: 2, item: 0),
            FeedIndexPath(section: 0, item: 0),
        ]
        #expect(InvertedAccessibilityOrder.topToBottom(paths) == [
            FeedIndexPath(section: 2, item: 0),
            FeedIndexPath(section: 1, item: 2),
            FeedIndexPath(section: 1, item: 0),
            FeedIndexPath(section: 0, item: 0),
        ])
    }

    @Test("Рост ячейки у визуального низа сдвигает offset, рост в кадре — нет")
    func offsetCompensation() {
        #expect(MeasuredOffsetCompensation.delta(itemMaxY: 40, viewportOffset: 100, heightDelta: 12) == 12)
        #expect(MeasuredOffsetCompensation.delta(itemMaxY: 180, viewportOffset: 100, heightDelta: 12) == 0)
        #expect(MeasuredOffsetCompensation.delta(itemMaxY: 40, viewportOffset: 100, heightDelta: 1) == 0)
    }

    private func row(text: String) -> TranscriptRow {
        TranscriptRow(
            message: Message(
                id: "m-\(text.count)",
                chatId: "c1",
                authorId: "u1",
                text: text,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                status: .sent,
                authorName: "A"
            ),
            dayTitle: nil,
            group: .single,
            showsAuthorName: false,
            showsAuthorAvatar: false,
            isOutgoing: true
        )
    }
}
