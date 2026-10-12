import Testing
@testable import MaxlyPresentation

struct RecordingPressStateTests {
    @Test func movementsAfterRecordingCancellationAreStillTheSameTouch() {
        var press = RecordingPressState()
        let began = press.begin()
        #expect(began)
        let first = press.generation
        let moved = press.begin()
        let movedAgain = press.begin()
        #expect(!moved)
        #expect(!movedAgain)
        #expect(press.generation == first)
        let ended = press.end(generation: first)
        #expect(ended)
        let beganAgain = press.begin()
        #expect(beganAgain)
        #expect(press.generation != first)
    }

    @Test func delayedCancellationCannotEndANewTouch() {
        var press = RecordingPressState()
        _ = press.begin()
        let old = press.generation
        let ended = press.end(generation: old)
        #expect(ended)
        let endedAgain = press.end(generation: old)
        #expect(!endedAgain)
        _ = press.begin()
        let staleEnded = press.end(generation: old)
        #expect(!staleEnded)
        #expect(press.active)
    }
}
