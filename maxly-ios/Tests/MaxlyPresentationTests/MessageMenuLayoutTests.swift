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
}
