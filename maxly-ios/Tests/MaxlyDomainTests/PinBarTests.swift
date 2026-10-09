import Foundation
import Testing
import MaxlyDomain

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

    @Test("Пуш закрепа доходит до слушателя")
    func hubDelivers() async {
        let hub = PinHub()
        let stream = hub.pins()
        let push = PinPush(chatId: "c", action: "pin", messageId: "m", count: 2)
        let task = Task { () -> PinPush? in
            for await item in stream { return item }
            return nil
        }
        try? await Task.sleep(for: .milliseconds(30))
        hub.publish(push)
        let got = await task.value
        #expect(got == push)
    }
}

@Suite("Несколько ответов опроса")
struct PollSeveralTests {
    @Test("Бит 2 маски — несколько ответов, остальные биты нет")
    func several() {
        #expect(PollContent.allowsSeveral(flags: 0) == false)
        #expect(PollContent.allowsSeveral(flags: 1) == false)
        #expect(PollContent.allowsSeveral(flags: 2) == true)
        #expect(PollContent.allowsSeveral(flags: 3) == true)
        let data = #"{"id":"p","title":"t","answers":[],"total":0}"#.data(using: .utf8)!
        let poll = try! JSONDecoder().decode(PollContent.self, from: data)
        #expect(poll.multiple == false)
    }
}
