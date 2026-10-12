import Testing
@testable import MaxlyPresentation

@Suite("Transcript: measured bottom, not requested bottom")
struct TranscriptBottomStateTests {
    @Test func requestDoesNotAcknowledgeUnreadMessages() {
        var state = TranscriptBottomState()
        state.received(5)
        state.beginFollowing()
        #expect(state.followsLatest)
        #expect(!state.atBottom)
        #expect(state.unseen == 5)
        #expect(state.showsButton(hasMessages: true))
        state.measuredLastRow(minY: nil, maxY: nil, viewportMin: 101, viewportMax: 772, userScrolling: false)
        #expect(!state.atBottom)
        #expect(state.unseen == 5)
    }

    @Test func loggedEmptyViewportCannotConfirmBottom() {
        var state = TranscriptBottomState()
        state.beginFollowing()
        // Oct 12: 50 loaded rows, UIScrollView at its estimated maximum, no measured row.
        state.measuredLastRow(minY: nil, maxY: nil, viewportMin: 101, viewportMax: 772, userScrolling: false)
        #expect(!state.atBottom)
        // First row reappeared with a 280-point blank gap below it: still not settled.
        state.measuredLastRow(minY: -312.7, maxY: 492, viewportMin: 101, viewportMax: 772, userScrolling: true)
        #expect(!state.atBottom)
        #expect(!state.followsLatest)
        state.measuredLastRow(minY: -45, maxY: 759.7, viewportMin: 101, viewportMax: 772, userScrolling: true)
        #expect(state.atBottom)
        #expect(state.followsLatest)
    }

    @Test func onlyMeasuredVisibleEndClearsUnreadCount() {
        var state = TranscriptBottomState()
        state.received(3)
        state.beginFollowing()
        state.measuredLastRow(minY: 1010, maxY: 1690, viewportMin: 101, viewportMax: 766, userScrolling: false)
        #expect(!state.atBottom && state.unseen == 3)
        state.measuredLastRow(minY: 200, maxY: 754, viewportMin: 101, viewportMax: 766, userScrolling: false)
        #expect(state.atBottom && state.unseen == 0)
    }

    @Test func fullyVisibleShortTranscriptNeedsNoArtificialGap() {
        var state = TranscriptBottomState()
        state.measuredLastRow(minY: 140, maxY: 200, viewportMin: 101, viewportMax: 766, userScrolling: false, contentFits: true)
        #expect(state.atBottom)
        state.measuredLastRow(minY: -200, maxY: -100, viewportMin: 101, viewportMax: 766, userScrolling: false, contentFits: true)
        #expect(!state.atBottom)
    }

    @Test func mediaGrowthRetainsIntentButNotFalsePosition() {
        var state = TranscriptBottomState()
        state.beginFollowing()
        state.measuredLastRow(minY: 200, maxY: 760, viewportMin: 101, viewportMax: 766, userScrolling: false)
        state.measuredLastRow(minY: 200, maxY: 1200, viewportMin: 101, viewportMax: 766, userScrolling: false)
        #expect(!state.atBottom && state.followsLatest)
        state.userTookOver()
        #expect(!state.followsLatest)
    }

    @Test func historyPlacementNeverEnablesAutomaticFollowing() {
        var state = TranscriptBottomState()
        state.beginFollowing()
        state.beginReadingHistory()
        state.measuredLastRow(minY: 200, maxY: 760, viewportMin: 101, viewportMax: 766, userScrolling: false)
        #expect(state.atBottom)
        #expect(!state.followsLatest)
    }

    @Test func invalidGeometryCannotConfirmBottom() {
        var state = TranscriptBottomState()
        state.measuredLastRow(minY: 0, maxY: .infinity, viewportMin: 0, viewportMax: 700, userScrolling: false)
        #expect(!state.atBottom)
        state.measuredLastRow(minY: 0, maxY: 50, viewportMin: 700, viewportMax: 700, userScrolling: false)
        #expect(!state.atBottom)
    }
}
