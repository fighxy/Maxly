import Foundation

/// Куски текста JSON как они есть, без разбора и пересборки: значение ключа объекта и
/// элементы массива. Нужны, чтобы нетронутые элементы разметки уходили обратно байт в байт.
public enum RawJSON {
    /// Элементы массива верхнего уровня строками, как в [json]. `nil` — не массив или битый JSON.
    public static func items(_ json: String) -> [String]? {
        let bytes = Array(json.utf8)
        var index = skipSpace(bytes, 0)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "[") else { return nil }
        index = skipSpace(bytes, index + 1)
        var result: [String] = []
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { return result }
        while index < bytes.count {
            guard let end = valueEnd(bytes, index) else { return nil }
            result.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = skipSpace(bytes, end)
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "]") { return result }
            guard bytes[index] == UInt8(ascii: ",") else { return nil }
            index = skipSpace(bytes, index + 1)
        }
        return nil
    }

    /// Значение ключа [key] объекта верхнего уровня строкой, как в [json]. `nil` — ключа нет.
    public static func value(_ key: String, in json: String) -> String? {
        let bytes = Array(json.utf8)
        var index = skipSpace(bytes, 0)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else { return nil }
        index = skipSpace(bytes, index + 1)
        while index < bytes.count, bytes[index] == UInt8(ascii: "\"") {
            guard let keyEnd = valueEnd(bytes, index) else { return nil }
            let name = String(decoding: bytes[index..<keyEnd], as: UTF8.self)
            index = skipSpace(bytes, keyEnd)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index = skipSpace(bytes, index + 1)
            guard let end = valueEnd(bytes, index) else { return nil }
            if decodedString(name) == key { return String(decoding: bytes[index..<end], as: UTF8.self) }
            index = skipSpace(bytes, end)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ",") else { return nil }
            index = skipSpace(bytes, index + 1)
        }
        return nil
    }

    private static func decodedString(_ literal: String) -> String? {
        guard let data = literal.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String
    }

    private static func skipSpace(_ bytes: [UInt8], _ start: Int) -> Int {
        var index = start
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        return index
    }

    /// Конец значения, которое начинается в [start] (индекс за последним байтом).
    private static func valueEnd(_ bytes: [UInt8], _ start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            var index = start + 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"): index += 2
                case UInt8(ascii: "\""): return index + 1
                default: index += 1
                }
            }
            return nil
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var index = start
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    guard let end = valueEnd(bytes, index) else { return nil }
                    index = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return index + 1 }
                default:
                    break
                }
                index += 1
            }
            return nil
        default:
            var index = start
            while index < bytes.count, ![UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
            return index > start ? index : nil
        }
    }
}
