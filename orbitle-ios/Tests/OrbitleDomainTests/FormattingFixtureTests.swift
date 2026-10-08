import Foundation
import Testing
@testable import OrbitleDomain

/// Общие с Kotlin сценарии разметки текста из `test-fixtures/formatting`. Формат файлов и
/// правила — в README рядом с ними.
@Suite("Форматирование: общие сценарии")
struct FormattingFixtureTests {
    static let folder = SharedFixtureFolder(folder: "formatting")
    static let played = [
        "parse-types", "parse-defaults", "parse-utf16", "parse-unknown", "parse-overlap",
        "serialize-merge", "serialize-trim", "serialize-utf16", "toggle", "replace", "edit",
    ]

    @Test("Сценарий проигрывается", arguments: played)
    func play(_ name: String) throws {
        let fixture = try Self.folder.load(name)
        for (label, item) in try Self.folder.cases(fixture, file: name) {
            switch fixture["kind"] as? String {
            case "parse": try Self.parse(item, label)
            case "serialize": try Self.serialize(item, label)
            case "toggle": try Self.toggle(item, label)
            case "replace": try Self.replace(item, label)
            case "edit": try Self.edit(item, label)
            default: Issue.record("\(name): неизвестный kind \(String(describing: fixture["kind"]))")
            }
        }
    }

    @Test("Каждый файл сценария проигрывается")
    func everyFixtureIsPlayed() throws {
        try Self.folder.checkPlayed(Self.played)
    }

    static func parse(_ item: [String: Any], _ label: String) throws {
        let text = item["text"] as? String ?? ""
        let expect = try FixtureValue.object(item["expect"], label)
        let want = try FixtureValue.spans(expect["spans"], label)
        let got = MessageMarkup.parse(item["elements"], text: text)
        #expect(got == want, "\(label): \(got)")
        for entry in try FixtureValue.objects(expect["spans"], label) {
            guard let covered = entry["text"] as? String else { continue }
            let span = try FixtureValue.span(entry, label)
            #expect(FixtureValue.utf16Slice(text, from: span.from, length: span.length) == covered, "\(label): кусок «\(covered)»")
        }
    }

    static func serialize(_ item: [String: Any], _ label: String) throws {
        let draft = item["text"] as? String ?? ""
        let expect = try FixtureValue.object(item["expect"], label)
        let trimmed = MessageMarkup.trimmed(draft, spans: try FixtureValue.spans(item["spans"], label))
        if let text = expect["text"] as? String {
            #expect(trimmed.text == text, "\(label): текст «\(trimmed.text)»")
        }
        let got = MessageMarkup.elements(trimmed.spans, text: trimmed.text)
        #expect(got == (try FixtureValue.elements(expect["elements"], label)), "\(label): \(got)")
        // Форма JSON для моста: у ссылки адрес в attributes, без лишних ключей.
        let json = got.map(\.json)
        for (index, map) in json.enumerated() where got[index].extra == nil {
            #expect(Set(map.keys).isSubset(of: ["type", "from", "length", "attributes", "entityId"]), "\(label): ключи \(index)")
        }
    }

    static func toggle(_ item: [String: Any], _ label: String) throws {
        let spans = try FixtureValue.spans(item["spans"], label)
        let selection = try FixtureValue.object(item["selection"], label)
        let start = try FixtureValue.int(selection["from"], label)
        let end = start + (try FixtureValue.int(selection["length"], label))
        guard let type = item["type"] as? String, let kind = MessageMarkup.kind(type: type) else {
            throw SharedFixtureError("\(label): нет type")
        }
        let got = kind == .link
            ? MessageMarkup.setLink(spans, start: start, end: end, url: FixtureValue.string(item["url"]))
            : MessageMarkup.toggle(spans, kind: kind, start: start, end: end)
        let want = try FixtureValue.spans(try FixtureValue.object(item["expect"], label)["spans"], label)
        #expect(got == want, "\(label): \(got)")
    }

    static func replace(_ item: [String: Any], _ label: String) throws {
        let edit = try FixtureValue.object(item["edit"], label)
        let got = MessageMarkup.replace(
            try FixtureValue.spans(item["spans"], label),
            at: try FixtureValue.int(edit["at"], label),
            removed: try FixtureValue.int(edit["removed"], label),
            inserted: try FixtureValue.int(edit["inserted"], label)
        )
        let want = try FixtureValue.spans(try FixtureValue.object(item["expect"], label)["spans"], label)
        #expect(got == want, "\(label): \(got)")
    }

    static func edit(_ item: [String: Any], _ label: String) throws {
        let original = try FixtureValue.object(item["original"], label)
        let draft = try FixtureValue.object(item["draft"], label)
        let expect = try FixtureValue.object(item["expect"], label)
        let originalText = original["text"] as? String ?? ""
        let plan = MessageMarkup.editRequest(
            originalText: originalText,
            originalSpans: MessageMarkup.parse(original["elements"], text: originalText),
            draft: draft["text"] as? String ?? "",
            spans: try FixtureValue.spans(draft["spans"], label)
        )
        let wantsRequest = expect["request"] as? Bool ?? false
        #expect((plan != nil) == wantsRequest, "\(label): запрос")
        guard let plan, wantsRequest else { return }
        #expect(plan.text == expect["text"] as? String, "\(label): текст")
        #expect(plan.elements == (try FixtureValue.elements(expect["elements"], label)), "\(label): \(plan.elements)")
        #expect(MessageMarkup.json(plan.elements).hasPrefix("["), "\(label): elements всегда список")
    }
}

@Suite("Форматирование: мелочи")
struct MessageMarkupTests {
    @Test("Пустой список elements — это «[]», а не пропуск")
    func emptyJSON() {
        #expect(MessageMarkup.json([]) == "[]")
    }

    @Test("Ссылка в JSON: адрес в attributes")
    func linkJSON() {
        let json = MessageMarkup.json([MessageMarkup.Element(type: "LINK", from: 0, length: 3, url: "https://max.ru")])
        #expect(json.contains("\"attributes\":{\"url\":\"https:\\/\\/max.ru\"}") || json.contains("\"attributes\":{\"url\":\"https://max.ru\"}"))
    }

    @Test("Адрес ссылки: схема по умолчанию https, пробелы — ошибка")
    func normalizeURL() {
        #expect(MessageMarkup.normalizeURL("  max.ru ") == "https://max.ru")
        #expect(MessageMarkup.normalizeURL("http://a.ru/x") == "http://a.ru/x")
        #expect(MessageMarkup.normalizeURL("mailto:a@b.ru") == "mailto:a@b.ru")
        #expect(MessageMarkup.normalizeURL("  ") == nil)
        #expect(MessageMarkup.normalizeURL("a b.ru") == nil)
    }

    @Test("Правка находится по общему началу и концу, курсор уточняет место")
    func diff() {
        let insert = MessageMarkup.diff(old: "abc", new: "abXc")
        #expect(insert.at == 2 && insert.removed == 0 && insert.inserted == 1)
        let repeated = MessageMarkup.diff(old: "аа", new: "ааа", cursor: 1)
        #expect(repeated.at == 0 && repeated.removed == 0 && repeated.inserted == 1)
        let emoji = MessageMarkup.diff(old: "a😀b", new: "ab")
        #expect(emoji.at == 1 && emoji.removed == 2 && emoji.inserted == 0)
    }

    @Test("Без текста length без значения — до конца, без переполнения")
    func toEnd() {
        let spans = MessageMarkup.parse([["type": "STRONG", "from": 2]], text: nil)
        #expect(spans == [TextSpan(kind: .strong, from: 2, length: MessageMarkup.toEnd)])
    }
}
