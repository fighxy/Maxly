import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

@Suite("Шапка списка чатов: истории, поиск и папки")
struct StoryStripMotionTests {
    /// Истории 0…100, поиск 100…152, папки с 152.
    private let header = ChatListHeaderGeometry(stories: 0...100, search: 100...152, folders: 152)

    @Test("Стопка у заголовка, пока истории спрятаны; без историй — всегда")
    func stack() {
        #expect(header.storiesHidden(at: 100))
        #expect(header.storiesHidden(at: 93))
        #expect(!header.storiesHidden(at: 80))
        #expect(!header.storiesHidden(at: 0))
        #expect(ChatListHeaderGeometry(search: 0...52, folders: 52).storiesHidden(at: 0))
    }

    @Test("Остановка посреди историй или поиска доводится до ближнего края")
    func snap() {
        #expect(header.snapTarget(at: 30) == 0)
        #expect(header.snapTarget(at: 60) == 100)
        #expect(header.snapTarget(at: 110) == 100)
        #expect(header.snapTarget(at: 140) == 152)
        #expect(header.snapTarget(at: 0) == nil)
        #expect(header.snapTarget(at: 100) == nil)
        #expect(header.snapTarget(at: 152) == nil)
        #expect(header.snapTarget(at: 400) == nil)
    }

    @Test("Инерция сверху вниз останавливается на поиске, палец — нет")
    func fling() {
        #expect(header.stopsFling(from: 120, to: 90, dragging: false, decelerating: true))
        #expect(!header.stopsFling(from: 120, to: 90, dragging: true, decelerating: false))
        #expect(!header.stopsFling(from: 90, to: 60, dragging: false, decelerating: true))
        #expect(!header.stopsFling(from: 300, to: 200, dragging: false, decelerating: true))
        #expect(!ChatListHeaderGeometry(search: 0...52).stopsFling(from: 30, to: 10, dragging: false, decelerating: true))
    }

    @Test("Папки закрепляются, когда дошли до панели навигации")
    func pinned() {
        #expect(!header.foldersPinned(at: 100))
        #expect(header.foldersPinned(at: 152))
        #expect(header.foldersPinned(at: 500))
        #expect(!ChatListHeaderGeometry(search: 0...52).foldersPinned(at: 500))
    }

    @Test("Где стоять со спрятанными и открытыми историями")
    func positions() {
        #expect(header.storiesHiddenTop == 100)
        #expect(header.storiesShownTop == 0)
        #expect(ChatListHeaderGeometry().storiesHiddenTop == nil)
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
