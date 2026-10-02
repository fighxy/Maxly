import Testing
@testable import OrbitlePresentation

@Suite("Лента: низ и кнопка «вниз»")
struct TranscriptBottomStateTests {
    @Test("Сначала внизу, кнопки нет; пальцем вверх — кнопка есть, у низа — снова нет")
    func showAndHide() {
        var state = TranscriptBottomState()
        #expect(state.atBottom)
        #expect(!state.showsButton(hasMessages: true))
        state.scrolled(distance: 300, dragging: true)
        #expect(state.showsButton(hasMessages: true))
        #expect(!state.showsButton(hasMessages: false))
        state.scrolled(distance: 10, dragging: false)
        #expect(!state.showsButton(hasMessages: true))
    }

    @Test("Рост содержимого без пальца не показывает кнопку; между порогами признак не мигает")
    func hysteresis() {
        var state = TranscriptBottomState()
        state.scrolled(distance: 500, dragging: false)
        #expect(state.atBottom)
        state.scrolled(distance: 40, dragging: true)
        #expect(state.atBottom)
        state.scrolled(distance: 65, dragging: true)
        #expect(!state.atBottom)
        state.scrolled(distance: 40, dragging: true)
        #expect(!state.atBottom)
        state.scrolled(distance: 24, dragging: true)
        #expect(state.atBottom)
    }

    @Test("Новые чужие копятся только вверху и сбрасываются у низа")
    func unseen() {
        var state = TranscriptBottomState()
        state.received(2)
        #expect(state.unseen == 0)
        state.scrolled(distance: 300, dragging: true)
        state.received(2)
        state.received(1)
        state.received(0)
        #expect(state.unseen == 3)
        state.scrolled(distance: 0, dragging: false)
        #expect(state.unseen == 0)
    }

    @Test("Касание «вниз»: кнопка уходит сразу, путь по ленте её не возвращает, затем доводка")
    func jump() {
        var state = TranscriptBottomState()
        state.scrolled(distance: 2_000, dragging: true)
        state.received(5)
        let id = state.beginJump()
        #expect(state.atBottom)
        #expect(state.unseen == 0)
        #expect(!state.showsButton(hasMessages: true))
        // Строки ещё не измерены: лента в пути далеко от низа. Остаток инерции не отменяет прыжок.
        state.scrolled(distance: 800, dragging: true)
        #expect(state.atBottom)
        #expect(state.jump == id)
        // iOS 17: метка низа за экраном, пока прыжок в пути.
        state.markerMoved(bottomY: 5_000, viewportHeight: 700)
        #expect(state.atBottom)
        #expect(state.finishJump(id))
        #expect(state.jump == nil)
        #expect(!state.finishJump(id))
    }

    @Test("Палец во время прыжка: доводки нет, лента снова может уйти от низа")
    func takeOver() {
        var state = TranscriptBottomState()
        state.scrolled(distance: 2_000, dragging: true)
        let id = state.beginJump()
        state.userTookOver()
        state.scrolled(distance: 900, dragging: true)
        #expect(!state.atBottom)
        #expect(!state.finishJump(id))
    }

    @Test("Повторное касание заменяет прыжок: доводит только последний")
    func repeatedTap() {
        var state = TranscriptBottomState()
        state.scrolled(distance: 2_000, dragging: true)
        let first = state.beginJump()
        let second = state.beginJump()
        #expect(first != second)
        #expect(!state.finishJump(first))
        #expect(state.finishJump(second))
    }

    @Test("iOS 17: метка низа на экране — внизу, ушла — нет; запас больше, пока внизу")
    func marker() {
        var state = TranscriptBottomState()
        state.markerMoved(bottomY: 750, viewportHeight: 700)
        #expect(state.atBottom)
        state.markerMoved(bottomY: 780, viewportHeight: 700)
        #expect(!state.atBottom)
        state.markerMoved(bottomY: 740, viewportHeight: 700)
        #expect(!state.atBottom)
        state.markerMoved(bottomY: 720, viewportHeight: 700)
        #expect(state.atBottom)
        state.markerMoved(bottomY: .infinity, viewportHeight: 700)
        #expect(!state.atBottom)
    }
}
