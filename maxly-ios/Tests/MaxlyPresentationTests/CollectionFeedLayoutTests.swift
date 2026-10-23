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

    @Test("Полный зазор шапки и поля, короткая лента садится на поле ввода")
    func chromeInsetsClearHeaderAndComposer() {
        // Перекрытие шапки 100 и поля 120: минимум сверху 106, снизу 130.
        // Видимая высота 564, контент 200, запас сверху 364, итог 470.
        let short = FeedOffset.chromeInsets(
            boundsHeight: 800, contentHeight: 200, headerOverlap: 100, composerOverlap: 120
        )
        #expect(short.top == 470)
        #expect(short.bottom == 130)
        let long = FeedOffset.chromeInsets(
            boundsHeight: 800, contentHeight: 2000, headerOverlap: 100, composerOverlap: 120
        )
        #expect(long.top == 106)
        #expect(long.bottom == 130)
        let empty = FeedOffset.chromeInsets(
            boundsHeight: 800, contentHeight: 0, headerOverlap: 0, composerOverlap: 0
        )
        #expect(empty.top == FeedOffset.baseTopInset)
        #expect(empty.bottom == FeedOffset.baseBottomInset)
        let fullBleed = FeedOffset.chromeInsets(
            boundsHeight: 844, contentHeight: 5000, headerOverlap: 101, composerOverlap: 78
        )
        #expect(fullBleed.top == 107)
        #expect(fullBleed.bottom == 88)
        #expect(FeedOffset.contentFits(contentHeight: 200, boundsHeight: 800, insetTop: 470, insetBottom: 130))
        #expect(!FeedOffset.contentFits(contentHeight: 2000, boundsHeight: 800, insetTop: 106, insetBottom: 130))
    }

    @Test("Неизмеренные края не удваивают safe area")
    func unresolvedChromeDoesNotDoubleCount() {
        #expect(FeedOffset.unresolvedHeader(safeTop: 0, windowTop: 47) == 101)
        #expect(FeedOffset.unresolvedHeader(safeTop: 101, windowTop: 47) == 101)
        #expect(FeedOffset.unresolvedHeader(safeTop: 47, windowTop: 47) == 101)
        #expect(FeedOffset.unresolvedComposer(safeBottom: 0, windowBottom: 34) == 78)
        #expect(FeedOffset.unresolvedComposer(safeBottom: 34, windowBottom: 34) == 78)
        #expect(FeedOffset.unresolvedComposer(safeBottom: 78, windowBottom: 34) == 78)
        #expect(FeedOffset.unresolvedComposer(safeBottom: 90, windowBottom: 34) == 90)
    }

    @Test("Перекрытие только там, где шапка и поле закрывают саму ленту")
    func overlapMatchesTheCollectionFrame() {
        #expect(FeedOffset.headerOverlap(frameMinY: 0, frameMaxY: 844, headerBottom: nil, unresolved: 101) == 101)
        #expect(FeedOffset.headerOverlap(frameMinY: 101, frameMaxY: 766, headerBottom: nil, unresolved: 101) == 0)
        #expect(FeedOffset.headerOverlap(frameMinY: 101, frameMaxY: 766, headerBottom: 155, unresolved: 101) == 54)
        #expect(FeedOffset.composerOverlap(
            frameMinY: 0, frameMaxY: 844, frameReachesScreenBottom: true, composerTop: 766, unresolved: 78
        ) == 78)
        #expect(FeedOffset.composerOverlap(
            frameMinY: 101, frameMaxY: 766, frameReachesScreenBottom: false, composerTop: 766, unresolved: 78
        ) == 0)
        #expect(FeedOffset.composerOverlap(
            frameMinY: 0, frameMaxY: 844, frameReachesScreenBottom: true, composerTop: nil, unresolved: 78
        ) == 78)
        #expect(FeedOffset.composerOverlap(
            frameMinY: 101, frameMaxY: 766, frameReachesScreenBottom: false, composerTop: nil, unresolved: 78
        ) == 0)
        let shrunk = FeedOffset.chromeInsets(
            boundsHeight: 665, contentHeight: 5000, headerOverlap: 0, composerOverlap: 0
        )
        #expect(shrunk.top == FeedOffset.baseTopInset)
        #expect(shrunk.bottom == FeedOffset.baseBottomInset)
    }

    @Test("Расстояние до читаемого низа вычитает перекрытие поля")
    func distanceAboveCoverSubtractsTheComposer() {
        #expect(FeedOffset.distanceAboveCover(rowMaxY: 756, viewportMaxY: 844, cover: 88) == 0)
        #expect(FeedOffset.distanceAboveCover(rowMaxY: 700, viewportMaxY: 844, cover: 88) == 56)
        #expect(FeedOffset.distanceAboveCover(rowMaxY: 756, viewportMaxY: 766, cover: 10) == 0)
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
