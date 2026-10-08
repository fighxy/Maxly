import Foundation
import Testing
@testable import OrbitleDomain

struct SharedFixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Каталог общих с Kotlin сценариев в `test-fixtures/<folder>`. Ресурсом пакета их не сделать:
/// SwiftPM не берёт файлы вне каталога пакета, поэтому путь ищется от этого файла вверх до
/// корня репозитория (как у сценариев прочтений и набора текста).
struct SharedFixtureFolder {
    let folder: String

    func directory() throws -> URL {
        let relative = "test-fixtures/\(folder)"
        let file = #filePath
        var components = URL(fileURLWithPath: file).deletingLastPathComponent().pathComponents
        while !components.isEmpty {
            let candidate = URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
                .appendingPathComponent(relative, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            components.removeLast()
        }
        throw SharedFixtureError("нет каталога \(relative) выше \(file)")
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory().path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    func load(_ name: String) throws -> [String: Any] {
        let url = try directory().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SharedFixtureError("\(name).json — не объект JSON")
        }
        #expect(object["name"] as? String == name, "\(name): name не совпадает с файлом")
        return object
    }

    /// Случаи файла: у каждого своя подпись `файл/случай` для сообщений.
    func cases(_ fixture: [String: Any], file: String) throws -> [(label: String, item: [String: Any])] {
        guard let list = fixture["cases"] as? [[String: Any]], !list.isEmpty else {
            throw SharedFixtureError("\(file): нет случаев")
        }
        return list.map { ("\(file)/\($0["name"] as? String ?? "?")", $0) }
    }

    /// Каждый файл каталога есть в [played], и наоборот.
    func checkPlayed(_ played: [String]) throws {
        let files = Set(try names())
        let known = Set(played)
        #expect(files.subtracting(known).isEmpty, "нет теста для файлов: \(files.subtracting(known).sorted())")
        #expect(known.subtracting(files).isEmpty, "нет файлов: \(known.subtracting(files).sorted())")
    }
}

/// Разбор значений JSON сценариев.
enum FixtureValue {
    static func object(_ value: Any?, _ context: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw SharedFixtureError("\(context): нет объекта") }
        return object
    }

    static func objects(_ value: Any?, _ context: String) throws -> [[String: Any]] {
        guard let list = value as? [[String: Any]] else { throw SharedFixtureError("\(context): нет списка объектов") }
        return list
    }

    static func int(_ value: Any?, _ context: String) throws -> Int {
        guard let number = MessageMarkup.number(value) else { throw SharedFixtureError("\(context): нет числа") }
        return number
    }

    static func long(_ value: Any?, _ context: String) throws -> Int64 {
        guard let number = MessageReaders.number(value) else { throw SharedFixtureError("\(context): нет числа") }
        return number
    }

    static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    static func string(_ value: Any?) -> String? {
        if isNull(value) { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.int64Value.description }
        return nil
    }

    /// Отрезок поля ввода `{type, from, length, url?}`.
    static func span(_ map: [String: Any], _ context: String) throws -> TextSpan {
        guard let type = map["type"] as? String, let kind = MessageMarkup.kind(type: type) else {
            throw SharedFixtureError("\(context): неизвестный type \(String(describing: map["type"]))")
        }
        return TextSpan(kind: kind, from: try int(map["from"], context), length: try int(map["length"], context), url: map["url"] as? String)
    }

    static func spans(_ value: Any?, _ context: String) throws -> [TextSpan] {
        if isNull(value) { return [] }
        return try objects(value, context).map { try span($0, context) }
    }

    /// Элемент сервера `{type, from, length, attributes?}` в сравнимом виде.
    static func element(_ map: [String: Any], _ context: String) throws -> MessageMarkup.Element {
        guard let type = map["type"] as? String else { throw SharedFixtureError("\(context): нет type") }
        let attributes = map["attributes"] as? [String: Any]
        return MessageMarkup.Element(type: type, from: try int(map["from"], context), length: try int(map["length"], context),
                                     url: attributes?["url"] as? String, entityId: string(map["entityId"]))
    }

    static func elements(_ value: Any?, _ context: String) throws -> [MessageMarkup.Element] {
        try objects(value, context).map { try element($0, context) }
    }

    /// Кусок текста по смещениям UTF-16.
    static func utf16Slice(_ text: String, from: Int, length: Int) -> String {
        let units = Array(text.utf16)
        guard from >= 0, length >= 0, from + length <= units.count else { return "<за границей>" }
        return String(utf16CodeUnits: Array(units[from..<(from + length)]), count: length)
    }
}
