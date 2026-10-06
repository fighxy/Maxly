import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Жест полосы историй")
struct StoryStripMotionTests {
    @Test("Поднятие от края прячет после порога")
    func liftCollapses() {
        #expect(abs(StoryStripMotion.reveal(expanded: true, drag: -40, height: 100, atTop: true) - 0.6) < 0.001)
        #expect(StoryStripMotion.settledExpanded(wasExpanded: true, drag: -40, atTop: true, threshold: 48))
        #expect(abs(StoryStripMotion.reveal(expanded: true, drag: -60, height: 100, atTop: true) - 0.4) < 0.001)
        #expect(!StoryStripMotion.settledExpanded(wasExpanded: true, drag: -60, atTop: true, threshold: 48))
    }

    @Test("Потянуть вниз открывает скрытую полосу")
    func pullOpens() {
        #expect(abs(StoryStripMotion.reveal(expanded: false, drag: 30, height: 100, atTop: true) - 0.3) < 0.001)
        #expect(!StoryStripMotion.settledExpanded(wasExpanded: false, drag: 30, atTop: true, threshold: 48))
        #expect(StoryStripMotion.settledExpanded(wasExpanded: false, drag: 48, atTop: true, threshold: 48))
    }

    @Test("В середине списка полоса не двигается")
    func midListStays() {
        #expect(StoryStripMotion.reveal(expanded: true, drag: -80, height: 100, atTop: false) == 1)
        #expect(StoryStripMotion.settledExpanded(wasExpanded: true, drag: -80, atTop: false, threshold: 48))
        #expect(StoryStripMotion.reveal(expanded: false, drag: 80, height: 100, atTop: false) == 0)
    }

    @Test("Обновление только у открытой полосы")
    func refresh() {
        #expect(StoryStripMotion.refreshesOnPull(expanded: true))
        #expect(!StoryStripMotion.refreshesOnPull(expanded: false))
    }

    @Test("Кольцо группы не садится на человека с тем же id")
    func ownerType() {
        let group = StoryRing(owner: StoryOwner(id: "10", kind: .chat), name: "Группа", updatedAt: Date(timeIntervalSince1970: 1), total: 1, read: 0)
        let person = StoryRing(owner: StoryOwner(id: "10"), name: "Иван", updatedAt: Date(timeIntervalSince1970: 1), total: 1, read: 0)
        #expect(StoryStripMotion.ringMatches(person, kind: .user))
        #expect(StoryStripMotion.ringMatches(group, kind: .chat))
        #expect(!StoryStripMotion.ringMatches(person, kind: .chat))
        #expect(!StoryStripMotion.ringMatches(group, kind: .channel))
        #expect(!StoryStripMotion.ringMatches(nil, kind: .user))
    }
}
