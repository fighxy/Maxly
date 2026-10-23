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
        let older = CollectionFeedLayout.height(index: 0, chronological: rows, maxWidth: 280, cache: cache)
        let newest = CollectionFeedLayout.height(index: 1, chronological: rows, maxWidth: 280, cache: cache)
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
        let older = CollectionFeedLayout.height(index: 0, chronological: rows, maxWidth: 280, cache: cache)
        let newest = CollectionFeedLayout.height(index: 1, chronological: rows, maxWidth: 280, cache: cache)
        #expect(older == 400)
        #expect(newest != 400)
    }

    @Test("Рост строки выше экрана сдвигает offset, рост в кадре — нет")
    func offsetCompensation() {
        #expect(FeedOffset.compensation(itemMaxY: 40, viewportOffset: 100, heightDelta: 12) == 12)
        #expect(FeedOffset.compensation(itemMaxY: 180, viewportOffset: 100, heightDelta: 12) == 0)
        #expect(FeedOffset.compensation(itemMaxY: 40, viewportOffset: 100, heightDelta: 1) == 0)
    }

    @Test("Якорь держит верх строки, цель ставит её у края, пределы не пробиваются")
    func anchorAndReveal() {
        let held = FeedOffset.restoring(rowMinY: 500, topInViewport: -20, minOffset: -10, maxOffset: 2000)
        #expect(held == 520)
        let top = FeedOffset.revealing(
            rowMinY: 1000, rowHeight: 40, anchor: 0,
            viewportHeight: 600, insetTop: 100, minOffset: -100, maxOffset: 5000
        )
        #expect(top == 900)
        let bottom = FeedOffset.revealing(
            rowMinY: 1000, rowHeight: 40, anchor: 1,
            viewportHeight: 600, insetTop: 100, minOffset: -100, maxOffset: 5000
        )
        #expect(bottom == 340)
        let clamped = FeedOffset.restoring(rowMinY: 10, topInViewport: 0, minOffset: 40, maxOffset: 30)
        #expect(clamped == 40)
    }

    @Test("Короткая лента получает запас сверху, длинная — только базовый зазор")
    func shortTranscriptSitsOnComposer() {
        let short = FeedOffset.shortTopInset(boundsHeight: 800, safeTop: 100, safeBottom: 120, contentHeight: 200)
        #expect(short == 370)
        let long = FeedOffset.shortTopInset(boundsHeight: 800, safeTop: 100, safeBottom: 120, contentHeight: 2000)
        #expect(long == FeedOffset.baseTopInset)
        let empty = FeedOffset.shortTopInset(boundsHeight: 800, safeTop: 0, safeBottom: 0, contentHeight: 0)
        #expect(empty == FeedOffset.baseTopInset)
        #expect(FeedOffset.contentFits(contentHeight: 200, boundsHeight: 800, insetTop: 470, insetBottom: 130))
        #expect(!FeedOffset.contentFits(contentHeight: 2000, boundsHeight: 800, insetTop: 106, insetBottom: 130))
    }

    @Test("Палец держит якорь, низ — только без пальца, история важнее прилипания")
    func settlePlan() {
        #expect(FeedSettle.plan(interacting: true, contentFits: false, stickToBottom: true, hasHistoryReveal: false, pinToLatest: false, hasAnchor: true) == .restore)
        #expect(FeedSettle.plan(interacting: true, contentFits: false, stickToBottom: true, hasHistoryReveal: false, pinToLatest: true, hasAnchor: false) == .keep)
        #expect(FeedSettle.plan(interacting: false, contentFits: true, stickToBottom: false, hasHistoryReveal: true, pinToLatest: false, hasAnchor: true) == .pinBottom)
        #expect(FeedSettle.plan(interacting: false, contentFits: false, stickToBottom: true, hasHistoryReveal: true, pinToLatest: false, hasAnchor: true) == .reveal)
        #expect(FeedSettle.plan(interacting: false, contentFits: false, stickToBottom: true, hasHistoryReveal: false, pinToLatest: false, hasAnchor: true) == .pinBottom)
        #expect(FeedSettle.plan(interacting: false, contentFits: false, stickToBottom: false, hasHistoryReveal: false, pinToLatest: true, hasAnchor: true) == .pinBottom)
        #expect(FeedSettle.plan(interacting: false, contentFits: false, stickToBottom: false, hasHistoryReveal: false, pinToLatest: false, hasAnchor: true) == .restore)
        #expect(FeedSettle.plan(interacting: false, contentFits: false, stickToBottom: false, hasHistoryReveal: false, pinToLatest: false, hasAnchor: false) == .keep)
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
