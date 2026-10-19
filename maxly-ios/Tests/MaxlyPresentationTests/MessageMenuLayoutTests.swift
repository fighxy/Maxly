import Foundation
import Testing
@testable import MaxlyPresentation

@Suite("Message menu viewport")
struct MessageMenuLayoutTests {
    @Test func expandedMenuFitsCompactAndLandscapeScreens() {
        for size in [CGSize(width: 296, height: 600), CGSize(width: 700, height: 250), CGSize(width: 180, height: 120)] {
            let bounds = CGRect(origin: CGPoint(x: 12, y: 20), size: size)
            for outgoing in [false, true] {
                let layout = MessageMenuLayout(bounds: bounds,
                    source: CGRect(x: -10, y: 900, width: 340, height: 1500), outgoing: outgoing,
                    actionHeight: 1000, actionWidth: 250, reactionWidth: 500, reactionHeight: 52)
                for rect in [layout.preview, layout.actions, layout.reactions] {
                    #expect(rect.minX >= bounds.minX)
                    #expect(rect.maxX <= bounds.maxX)
                    #expect(rect.minY >= bounds.minY)
                    #expect(rect.maxY <= bounds.maxY)
                }
                #expect(layout.reactions.maxY <= layout.preview.minY)
                #expect(layout.preview.maxY <= layout.actions.minY)
                #expect(layout.actions.height < 1000)
            }
        }
    }

    @Test func shortBubbleIsNotStretchedAndKeepsItsPosition() {
        let source = CGRect(x: 30, y: 180, width: 150, height: 32)
        let layout = MessageMenuLayout(bounds: CGRect(x: 12, y: 60, width: 366, height: 700),
            source: source, outgoing: false, actionHeight: 240, actionWidth: 250,
            reactionWidth: 276, reactionHeight: 52)
        #expect(layout.preview == source)
        #expect(layout.actions.height == 240)
    }

    @Test func noReactionsReserveNoTopSpace() {
        let layout = MessageMenuLayout(bounds: CGRect(x: 12, y: 60, width: 366, height: 700),
            source: CGRect(x: 230, y: 0, width: 140, height: 100), outgoing: true,
            actionHeight: 240, actionWidth: 250, reactionWidth: 0, reactionHeight: 0)
        #expect(layout.preview.minY == 60)
        #expect(layout.reactions.height == 0)
        #expect(layout.actions.maxX == layout.preview.maxX)
    }

    /// A tall photo (Ivan's report): the bubble is scaled down so the reactions bar stays
    /// fully on screen above it and the actions below it.
    @Test func tallPhotoIsScaledSoReactionsAndActionsStayVisible() {
        let bounds = CGRect(x: 12, y: 12, width: 369, height: 643)
        let source = CGRect(x: 16, y: 10, width: 300, height: 430)
        let layout = MessageMenuLayout(bounds: bounds, source: source, outgoing: false,
            actionHeight: 287, actionWidth: 250, reactionWidth: 276, reactionHeight: 52)
        #expect(layout.reactions.minY >= bounds.minY)
        #expect(layout.reactions.height == 52)
        #expect(layout.reactions.maxY <= layout.preview.minY)
        #expect(layout.preview.maxY <= layout.actions.minY)
        #expect(layout.actions.maxY <= bounds.maxY)
        #expect(layout.actions.height == 287)
        #expect(layout.previewScale < 1)
        #expect(layout.previewScale >= MessageMenuLayout.minimumPreviewScale)
        #expect(!layout.previewClipped)
        #expect(abs(layout.preview.height - source.height * layout.previewScale) < 0.001)
        #expect(abs(layout.preview.width - source.width * layout.previewScale) < 0.001)
        #expect(layout.preview.minX == source.minX)
    }

    @Test func scaledOutgoingBubbleKeepsItsTrailingEdge() {
        let source = CGRect(x: 80, y: 300, width: 290, height: 600)
        let layout = MessageMenuLayout(bounds: CGRect(x: 12, y: 12, width: 369, height: 760),
            source: source, outgoing: true, actionHeight: 240, actionWidth: 250,
            reactionWidth: 276, reactionHeight: 52)
        #expect(layout.previewScale < 1)
        #expect(abs(layout.preview.maxX - source.maxX) < 0.001)
        #expect(abs(layout.actions.maxX - source.maxX) < 0.001)
    }

    /// Very long text: scaling stops at the readable minimum and the rest is clipped,
    /// the reactions bar and the actions still fit.
    @Test func veryLongTextIsClippedAtTheMinimumScale() {
        let bounds = CGRect(x: 12, y: 12, width: 369, height: 643)
        let layout = MessageMenuLayout(bounds: bounds,
            source: CGRect(x: 16, y: -900, width: 300, height: 2400), outgoing: false,
            actionHeight: 287, actionWidth: 250, reactionWidth: 276, reactionHeight: 52)
        #expect(layout.previewScale == MessageMenuLayout.minimumPreviewScale)
        #expect(layout.previewClipped)
        #expect(layout.reactions.minY == bounds.minY)
        #expect(layout.reactions.maxY <= layout.preview.minY)
        #expect(layout.preview.maxY <= layout.actions.minY)
        #expect(layout.actions.maxY <= bounds.maxY)
    }

    @Test func bubbleNearTheEdgesShiftsInsideTheViewport() {
        let bounds = CGRect(x: 12, y: 12, width: 369, height: 643)
        let top = MessageMenuLayout(bounds: bounds, source: CGRect(x: 16, y: 0, width: 200, height: 80),
            outgoing: false, actionHeight: 240, actionWidth: 250, reactionWidth: 276, reactionHeight: 52)
        #expect(top.reactions.minY == bounds.minY)
        #expect(top.preview.minY == bounds.minY + 60)
        #expect(top.previewScale == 1)
        let bottom = MessageMenuLayout(bounds: bounds, source: CGRect(x: 16, y: 600, width: 200, height: 80),
            outgoing: false, actionHeight: 240, actionWidth: 250, reactionWidth: 276, reactionHeight: 52)
        #expect(bottom.actions.maxY == bounds.maxY)
        #expect(bottom.preview.height == 80)
        #expect(bottom.reactions.maxY <= bottom.preview.minY)
    }
}
