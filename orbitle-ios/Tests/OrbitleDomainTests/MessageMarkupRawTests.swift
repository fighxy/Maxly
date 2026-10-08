import Foundation
import Testing
@testable import OrbitleDomain

@Suite("Разметка: элементы сервера как пришли")
struct MessageMarkupRawTests {
    /// Порядок ключей, пробелы, `entityId` числом и незнакомые ключи — как прислал сервер.
    let elements = #"[{"length":4,"type":"STRONG","from":0,"style":{"tone":2}}, {"type":"LINK","from":5,"length":3,"attributes":{"url":"https://a.b","preview":false},"v":1.5},{"type":"FUTURE","from":0,"length":2,"payload":[1,{"x":"}"}]}]"#
    let text = "abcd efg"

    @Test("Куски JSON: элементы массива и значение ключа без пересборки")
    func rawPieces() {
        let items = RawJSON.items(elements)
        #expect(items?.count == 3)
        #expect(items?.first == #"{"length":4,"type":"STRONG","from":0,"style":{"tone":2}}"#)
        #expect(items?.last == #"{"type":"FUTURE","from":0,"length":2,"payload":[1,{"x":"}"}]}"#)
        let content = #"{"text":"a\"b","elements": [ {"type":"STRONG","from":0,"length":1} ] ,"edited":true}"#
        #expect(RawJSON.value("elements", in: content) == #"[ {"type":"STRONG","from":0,"length":1} ]"#)
        #expect(RawJSON.value("edited", in: content) == "true")
        #expect(RawJSON.value("nope", in: content) == nil)
        #expect(RawJSON.items("{}") == nil)
    }

    @Test("Нетронутые элементы уходят байт в байт, правка текста после них их не меняет")
    func untouchedRoundTrip() throws {
        let spans = MessageMarkup.parse(json: elements, text: text)
        #expect(spans.count == 3)
        let items = try #require(RawJSON.items(elements))
        // Текст дописан в конце: отрезки не сдвинулись.
        let request = try #require(MessageMarkup.editRequest(originalText: text, originalSpans: spans, draft: text + " h", spans: spans))
        let sent = MessageMarkup.json(request.elements)
        for item in items { #expect(sent.contains(item), "\(item)") }
    }

    @Test("Сдвинутый элемент пишется заново, но с ключами, которых приложение не знает")
    func movedKeepsKeys() throws {
        let spans = MessageMarkup.parse(json: elements, text: text)
        let moved = MessageMarkup.replace(spans, at: 0, removed: 0, inserted: 2)
        let sent = MessageMarkup.json(MessageMarkup.elements(moved, text: "xx" + text))
        let objects = try #require(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [[String: Any]])
        let strong = try #require(objects.first { $0["type"] as? String == "STRONG" })
        #expect(strong["from"] as? Int == 2)
        #expect((strong["style"] as? [String: Any])?["tone"] as? Int == 2)
        let link = try #require(objects.first { $0["type"] as? String == "LINK" })
        #expect((link["attributes"] as? [String: Any])?["preview"] as? Bool == false)
        #expect(link["v"] as? Double == 1.5)
    }

    @Test("Сравнение отрезков не смотрит на исходный текст элемента")
    func rawNotInEquality() {
        let a = TextSpan(kind: .strong, from: 0, length: 1, raw: #"{"type":"STRONG","from":0,"length":1}"#)
        let b = TextSpan(kind: .strong, from: 0, length: 1)
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }
}
