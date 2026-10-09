import Testing
@testable import MaxlyPresentation

@Suite("Лента: низ и кнопка «вниз»")
struct TranscriptBottomStateTests {
    @Test("Переход к ответу или непрочитанным отключает удержание низа без жеста")
    func readingHistory() {
        var state = TranscriptBottomState()
        let jump = state.beginJump()
        state.beginReadingHistory()
        #expect(!state.atBottom)
        #expect(state.jump == nil)
        let completed = state.finishJump(jump)
        #expect(!completed)
        state.received(2)
        state.markerMoved(bottomY: .infinity, viewportHeight: 700, dragging: false)
        #expect(state.unseen == 2)
        #expect(state.showsButton(hasMessages: true))
        state.beginReadingHistory()
        #expect(state.unseen == 2)
        state.markerMoved(bottomY: 700, viewportHeight: 700, dragging: false)
        #expect(state.atBottom && state.unseen == 0)
    }

    @Test("Открытие на непрочитанных: прежнее положение у низа не залипает признаком «внизу»")
    func staleBottomAfterPlacingInHistory() {
        var state = TranscriptBottomState()
        state.beginReadingHistory()
        // До прокрутки к разделителю лента ещё у низа и успевает о себе сообщить.
        state.scrolled(distance: 10, dragging: false)
        #expect(state.atBottom)
        // Прокрутка к разделителю дошла: признак снимается и без пальца.
        state.scrolled(distance: 1_500, dragging: false)
        #expect(!state.atBottom)
        state.scrolled(distance: 10, dragging: false)
        state.markerMoved(bottomY: .infinity, viewportHeight: 700, dragging: false)
        #expect(!state.atBottom)
        // Палец взял ленту — снова обычные правила: рост содержимого признак не снимает.
        state.userTookOver()
        state.scrolled(distance: 10, dragging: false)
        state.scrolled(distance: 500, dragging: false)
        state.markerMoved(bottomY: .infinity, viewportHeight: 700, dragging: false)
        #expect(state.atBottom)
    }

    @Test("Касание «вниз» после открытия в истории возвращает обычное удержание низа")
    func jumpEndsPlacedHistory() {
        var state = TranscriptBottomState()
        state.beginReadingHistory()
        let id = state.beginJump()
        _ = state.finishJump(id)
        state.scrolled(distance: 400, dragging: false)
        #expect(state.atBottom)
    }

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
        // `finishJump` меняет состояние, поэтому вызывается вне `#expect`.
        let finished = state.finishJump(id)
        #expect(finished)
        #expect(state.jump == nil)
        let again = state.finishJump(id)
        #expect(!again)
    }

    @Test("Палец во время прыжка: доводки нет, лента снова может уйти от низа")
    func takeOver() {
        var state = TranscriptBottomState()
        state.scrolled(distance: 2_000, dragging: true)
        let id = state.beginJump()
        state.userTookOver()
        state.scrolled(distance: 900, dragging: true)
        #expect(!state.atBottom)
        let finished = state.finishJump(id)
        #expect(!finished)
    }

    @Test("Повторное касание заменяет прыжок: доводит только последний")
    func repeatedTap() {
        var state = TranscriptBottomState()
        state.scrolled(distance: 2_000, dragging: true)
        let first = state.beginJump()
        let second = state.beginJump()
        #expect(first != second)
        let stale = state.finishJump(first)
        let latest = state.finishJump(second)
        #expect(!stale)
        #expect(latest)
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

    @Test("iOS 18: у самого низа кнопка прячется по метке, даже если расстояние до низа не дошло до порога")
    func markerHidesAtBottom() {
        var state = TranscriptBottomState()
        state.markerMoved(bottomY: 3_000, viewportHeight: 700, dragging: true)
        #expect(state.showsButton(hasMessages: true))
        // Расстояние у низа завышено отступом под поле ввода: само по себе признак не включит.
        state.scrolled(distance: 90, dragging: false)
        #expect(state.showsButton(hasMessages: true))
        state.markerMoved(bottomY: 700, viewportHeight: 700, dragging: true)
        #expect(!state.showsButton(hasMessages: true))
    }

    @Test("iOS 18: без пальца метка за экраном (картинка выросла, лента не тронута) кнопку не показывает")
    func markerGrowthWithoutFinger() {
        var state = TranscriptBottomState()
        state.markerMoved(bottomY: 1_200, viewportHeight: 700, dragging: false)
        #expect(state.atBottom)
        // Ленивая лента убрала метку — тоже не повод без пальца.
        state.markerMoved(bottomY: .infinity, viewportHeight: 700, dragging: false)
        #expect(state.atBottom)
        state.markerMoved(bottomY: .infinity, viewportHeight: 700, dragging: true)
        #expect(!state.atBottom)
    }
}
