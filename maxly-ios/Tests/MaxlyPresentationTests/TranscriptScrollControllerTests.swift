import Testing
@testable import MaxlyPresentation

@Suite("Transcript scroll ownership")
struct TranscriptScrollControllerTests {
    @Test func newerCommandSupersedesOldCompletion() throws {
        var controller = TranscriptScrollController()
        controller.start(id: "old", anchor: 0.5, latest: false)
        let old = try #require(controller.request)
        controller.start(id: "latest", anchor: 1, latest: true)
        let current = try #require(controller.request)
        #expect(old.token != current.token)
        let stale = controller.finish(old.token)
        #expect(!stale)
        #expect(controller.request == current)
        let finished = controller.finish(current.token)
        #expect(finished)
        #expect(controller.request == nil)
    }

    @Test func touchOrDisappearanceInvalidatesPendingWork() throws {
        var controller = TranscriptScrollController()
        controller.start(id: "message", anchor: 1, latest: true)
        let pending = try #require(controller.request)
        controller.cancel()
        let finished = controller.finish(pending.token)
        #expect(!finished)
        controller.start(id: "message", anchor: 1, latest: true)
        #expect(controller.request?.token != pending.token)
    }

    @Test func targetMustBeVisibleAndAligned() {
        #expect(!TranscriptScrollController.reached(anchor: 1, rowMin: 1010, rowMax: 1690, viewportMin: 101, viewportMax: 766))
        #expect(!TranscriptScrollController.reached(anchor: 1, rowMin: -312, rowMax: 492, viewportMin: 101, viewportMax: 772))
        #expect(TranscriptScrollController.reached(anchor: 1, rowMin: -45, rowMax: 759.7, viewportMin: 101, viewportMax: 772))
        #expect(!TranscriptScrollController.reached(anchor: 1, rowMin: 0, rowMax: .nan, viewportMin: 101, viewportMax: 772))
    }

    @Test func anchorsWorkForTallPostsAndSearch() {
        #expect(TranscriptScrollController.reached(anchor: 0.5, rowMin: -100, rowMax: 900, viewportMin: 100, viewportMax: 700))
        #expect(TranscriptScrollController.reached(anchor: 0, rowMin: 100, rowMax: 900, viewportMin: 100, viewportMax: 700))
        #expect(!TranscriptScrollController.reached(anchor: 0, rowMin: 200, rowMax: 900, viewportMin: 100, viewportMax: 700))
    }
}
