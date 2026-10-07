import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Полоса историй в шапке списка")
struct StoryStripMotionTests {
    @Test("Свёрнута по умолчанию; потянуть вниз от верха пальцем — раскрывается")
    func pullExpands() {
        var motion = StoryStripMotion()
        #expect(!motion.expanded)
        #expect(motion.moved(gap: 40, dragging: true, decelerating: false, hasStories: true) == .none)
        #expect(motion.moved(gap: 64, dragging: true, decelerating: false, hasStories: true) == .expand)
        #expect(motion.expanded)
    }

    @Test("Долёт по инерции до верха полосу не раскрывает")
    func flingDoesNotExpand() {
        var motion = StoryStripMotion()
        #expect(motion.moved(gap: 120, dragging: false, decelerating: true, hasStories: true) == .none)
        #expect(motion.moved(gap: 120, dragging: false, decelerating: false, hasStories: true) == .none)
        #expect(!motion.expanded)
    }

    @Test("Список уехал под шапку — свёрнута, и пальцем, и по инерции")
    func scrollCollapses() {
        var motion = StoryStripMotion(expanded: true)
        #expect(motion.moved(gap: -10, dragging: true, decelerating: false, hasStories: true) == .none)
        #expect(motion.moved(gap: -24, dragging: true, decelerating: false, hasStories: true) == .collapse)
        var flung = StoryStripMotion(expanded: true)
        #expect(flung.moved(gap: nil, dragging: false, decelerating: true, hasStories: true) == .collapse)
    }

    @Test("Сдвиг списка от смены высоты шапки не переключает полосу обратно до конца жеста")
    func settlingUntilScrollEnds() {
        var motion = StoryStripMotion()
        #expect(motion.moved(gap: 70, dragging: true, decelerating: false, hasStories: true) == .expand)
        // Шапка выросла, верх списка оказался под ней — тот же жест.
        #expect(motion.moved(gap: -50, dragging: true, decelerating: false, hasStories: true) == .none)
        #expect(motion.expanded)
        motion.scrollEnded()
        #expect(motion.moved(gap: -30, dragging: true, decelerating: false, hasStories: true) == .collapse)
        // Шапка уменьшилась, список будто потянут вниз — тот же жест, без раскрытия.
        #expect(motion.moved(gap: 90, dragging: true, decelerating: false, hasStories: true) == .none)
        #expect(!motion.expanded)
    }

    @Test("Без пальца и инерции (программная прокрутка) ничего не переключается")
    func programmaticMovesIgnored() {
        var motion = StoryStripMotion(expanded: true)
        #expect(motion.moved(gap: -200, dragging: false, decelerating: false, hasStories: true) == .none)
        #expect(motion.expanded)
    }

    @Test("Историй не стало — полоса сворачивается; касание без историй не раскрывает")
    func noStories() {
        var motion = StoryStripMotion(expanded: true)
        #expect(motion.moved(gap: 0, dragging: false, decelerating: false, hasStories: false) == .collapse)
        #expect(motion.toggle(hasStories: false) == .none)
        #expect(motion.toggle(hasStories: true) == .expand)
        #expect(motion.toggle(hasStories: true) == .collapse)
    }

    @Test("Кольцо группы не садится на человека с тем же id")
    func ownerType() {
        let group = StoryRing(owner: StoryOwner(id: "10", kind: .chat), name: "Группа", updatedAt: Date(timeIntervalSince1970: 1), total: 1, read: 0)
        let person = StoryRing(owner: StoryOwner(id: "10"), name: "Иван", updatedAt: Date(timeIntervalSince1970: 1), total: 1, read: 0)
        #expect(StoryStripMotion.ringMatches(person, kind: .user))
        #expect(StoryStripMotion.ringMatches(group, kind: .chat))
        #expect(!StoryStripMotion.ringMatches(person, kind: .chat))
        #expect(!StoryStripMotion.ringMatches(group, kind: .channel))
        #expect(!StoryStripMotion.ringMatches(group, kind: .user))
        #expect(!StoryStripMotion.ringMatches(nil, kind: .user))
    }
}
