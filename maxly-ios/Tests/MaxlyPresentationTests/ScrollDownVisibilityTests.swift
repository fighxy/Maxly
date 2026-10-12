import Testing
@testable import MaxlyPresentation

struct ScrollDownVisibilityTests {
    @Test func atBottomWithComposerInsetIsZero() {
        // 2000 содержимого, экран 800, снизу 120 под поле ввода, смещение у самого низа.
        let d = ScrollDownVisibility.distanceFromBottom(contentHeight: 2000, offsetY: 1320, viewportHeight: 800, insetTop: 100, insetBottom: 120)
        #expect(d == 0)
    }

    @Test func bounceBelowBottomIsZero() {
        let d = ScrollDownVisibility.distanceFromBottom(contentHeight: 2000, offsetY: 1400, viewportHeight: 800, insetTop: 100, insetBottom: 120)
        #expect(d == 0)
    }

    @Test func shortContentNeverFar() {
        let d = ScrollDownVisibility.distanceFromBottom(contentHeight: 300, offsetY: -100, viewportHeight: 800, insetTop: 100, insetBottom: 120)
        #expect(d == 0)
    }

    @Test func scrolledUpDistance() {
        let d = ScrollDownVisibility.distanceFromBottom(contentHeight: 2000, offsetY: 320, viewportHeight: 800, insetTop: 100, insetBottom: 120)
        #expect(d == 1000)
    }

    @Test func hiddenAtBottomAndSmallScroll() {
        var v = ScrollDownVisibility()
        v.update(distance: 0, visibleHeight: 600)
        #expect(!v.shown)
        v.update(distance: 300, visibleHeight: 600)
        #expect(!v.shown)
    }

    @Test func hysteresis() {
        var v = ScrollDownVisibility()
        let shownChanged = v.update(distance: 500, visibleHeight: 600)
        #expect(shownChanged)
        #expect(v.shown)
        v.update(distance: 200, visibleHeight: 600)
        #expect(v.shown)
        let hiddenChanged = v.update(distance: 40, visibleHeight: 600)
        #expect(hiddenChanged)
        #expect(!v.shown)
        v.update(distance: 300, visibleHeight: 600)
        #expect(!v.shown)
    }

    @Test func minimumThresholdOnSmallViewport() {
        var v = ScrollDownVisibility()
        v.update(distance: 150, visibleHeight: 100)
        #expect(!v.shown)
        v.update(distance: 210, visibleHeight: 100)
        #expect(v.shown)
    }

    @Test func resetHides() {
        var v = ScrollDownVisibility()
        v.update(distance: 1000, visibleHeight: 600)
        v.reset()
        #expect(!v.shown)
    }
}
