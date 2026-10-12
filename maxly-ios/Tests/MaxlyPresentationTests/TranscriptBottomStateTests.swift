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
    @Test func visibleLastMessageHidesButtonWithoutConfirmingAlignment() {
        var state = TranscriptBottomState()
        state.received(3)
        // The last message ends 60 pt above the composer; older history is offscreen.
        state.measuredLastRow(minY: 540, maxY: 700, viewportMin: 100, viewportMax: 760, userScrolling: false)
        #expect(!state.showsButton(hasMessages: true))
        #expect(!state.atBottom)
        #expect(state.unseen == 3)
        // Growing media hides the message end below the composer again.
        state.measuredLastRow(minY: 540, maxY: 900, viewportMin: 100, viewportMax: 760, userScrolling: false)
        #expect(state.showsButton(hasMessages: true))
    }

    @Test func onlyTheEndOfATallMessageNeedsToBeVisible() {
        var state = TranscriptBottomState()
        state.measuredLastRow(minY: -600, maxY: 710, viewportMin: 100, viewportMax: 760, userScrolling: false)
        #expect(!state.showsButton(hasMessages: true))
        state.measuredLastRow(minY: -600, maxY: 90, viewportMin: 100, viewportMax: 760, userScrolling: false)
        #expect(state.showsButton(hasMessages: true))
        #expect(!state.showsButton(hasMessages: false))
    }


    @Test func shortTranscriptUnderGlassHeaderHidesButton() {
        // Oct 12, 14:59: one missed call under the header glass, area starting below the banners.
        var state = TranscriptBottomState()
        state.received(1)
        state.measuredLastRow(minY: 200, maxY: 243, viewportMin: 260, viewportMax: 600, userScrolling: false, contentFits: true, buttonMin: 59)
        #expect(state.lastEndVisible)
        #expect(!state.showsButton(hasMessages: true))
        // The end scrolled above the list itself: the button is back.
        state.measuredLastRow(minY: -100, maxY: 40, viewportMin: 260, viewportMax: 600, userScrolling: true, buttonMin: 59)
        #expect(state.showsButton(hasMessages: true))
    }
}
