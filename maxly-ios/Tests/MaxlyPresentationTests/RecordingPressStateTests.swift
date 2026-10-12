import Testing
@testable import MaxlyPresentation

struct RecordingPressStateTests {
    @Test func movementsAfterRecordingCancellationAreStillTheSameTouch() {
        var press = RecordingPressState()
        #expect(press.begin())
        let first = press.generation
        #expect(!press.begin())
        #expect(!press.begin())
        #expect(press.generation == first)
        #expect(press.end(generation: first))
        #expect(press.begin())
        #expect(press.generation != first)
    }

    @Test func delayedCancellationCannotEndANewTouch() {
        var press = RecordingPressState()
        _ = press.begin()
        let old = press.generation
        #expect(press.end(generation: old))
        #expect(!press.end(generation: old))
        _ = press.begin()
        #expect(!press.end(generation: old))
        #expect(press.active)
    }
}
