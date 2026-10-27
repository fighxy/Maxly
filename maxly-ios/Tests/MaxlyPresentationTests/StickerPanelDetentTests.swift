import Testing
@testable import MaxlyPresentation

@Suite("Панель эмодзи и стикеров: высота")
struct StickerPanelDetentTests {
    private func settle(expanded: Bool = false, _ translation: Double, predicted: Double? = nil) -> StickerPanelDetent {
        StickerPanelDetent.settle(
            expanded: expanded, collapsedHeight: 300, expandedHeight: 700,
            translation: translation, predicted: predicted ?? translation
        )
    }

    @Test("Вверх за середину — вытянута, не дотянул — обратно на место клавиатуры")
    func expandOrStay() {
        #expect(settle(250) == .expanded)
        #expect(settle(150) == .collapsed)
        // Короткий быстрый взмах вверх: инерция доносит за середину.
        #expect(settle(60, predicted: 320) == .expanded)
    }

    @Test("Вытянутая вниз возвращается к клавиатуре, даже резким взмахом")
    func collapseFromExpanded() {
        #expect(settle(expanded: true, -250) == .collapsed)
        #expect(settle(expanded: true, -100) == .expanded)
        #expect(settle(expanded: true, -380, predicted: -900) == .collapsed)
    }

    @Test("Стянутая ниже клавиатуры закрывается")
    func close() {
        #expect(settle(-90) == .closed)
        #expect(settle(-30, predicted: -200) == .closed)
        #expect(settle(-30) == .collapsed)
    }

    @Test("Под пальцем высота не ниже половины клавиатурной и не выше вытянутой")
    func liveHeight() {
        #expect(StickerPanelDetent.height(expanded: false, collapsedHeight: 300, expandedHeight: 700, translation: 120) == 420)
        #expect(StickerPanelDetent.height(expanded: false, collapsedHeight: 300, expandedHeight: 700, translation: -400) == 150)
        #expect(StickerPanelDetent.height(expanded: true, collapsedHeight: 300, expandedHeight: 700, translation: 50) == 700)
    }
}
