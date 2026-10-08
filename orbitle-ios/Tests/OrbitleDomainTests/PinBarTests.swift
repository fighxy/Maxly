import Testing
import OrbitleDomain

@Suite("Плашка закрепов")
struct PinBarTests {
    @Test("Касание идёт к более старому и по кругу, счётчик только когда их несколько")
    func cycle() {
        var bar = PinBar(pins: [
            ChatPin(messageId: "3", text: "новый"),
            ChatPin(messageId: "2", text: "средний"),
            ChatPin(messageId: "1", text: "старый"),
        ])
        #expect(bar.counter == "1 из 3")
        #expect(bar.advance() == "3")
        #expect(bar.current?.messageId == "2")
        #expect(bar.counter == "2 из 3")
        #expect(bar.advance() == "2")
        #expect(bar.advance() == "1")
        #expect(bar.current?.messageId == "3")
        var single = PinBar(pins: [ChatPin(messageId: "1", text: "один")])
        #expect(single.counter == nil)
        #expect(single.advance() == "1")
        #expect(single.current?.messageId == "1")
    }

    @Test("Событие закрепляет, снимает один и снимает все")
    func events() {
        var bar = PinBar()
        bar.apply(action: "pin", messageId: "1", text: "первый")
        bar.apply(action: "pin", messageId: "2", text: "второй")
        bar.apply(action: "pin", messageId: "2", text: "ещё раз")
        #expect(bar.pins.map(\.messageId) == ["2", "1"])
        #expect(bar.current?.text == "ещё раз")
        bar.apply(action: "unpin", messageId: "2")
        #expect(bar.current?.messageId == "1")
        bar.apply(action: "unpinAll", messageId: "")
        #expect(bar.pins.isEmpty)
        #expect(bar.current == nil)
        bar.apply(action: "other", messageId: "9", text: "нет")
        #expect(bar.pins.isEmpty)
    }
}
