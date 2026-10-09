import Foundation
import Testing
@testable import MaxlyDomain

@Suite("Своя позиция чата")
struct OwnReadMarkTests {
    @Test("Своя позиция чата — самая свежая из карточки, пуша и местной")
    func ownPosition() {
        #expect(OwnReadMark.position(card: 1_200, pushed: 900, local: 0) == 1_200)
        #expect(OwnReadMark.position(card: 1_200, pushed: 1_500, local: 0) == 1_500)
        // Отметки скрыты: сервер нашу не получил, местная новее.
        #expect(OwnReadMark.position(card: 1_200, pushed: 0, local: 5_000) == 5_000)
        // Местная старше серверной: серверная не откатывается.
        #expect(OwnReadMark.position(card: 1_200, pushed: 0, local: 600) == 1_200)
        #expect(OwnReadMark.position(card: 0, pushed: 0, local: 0) == 0)
    }
}
