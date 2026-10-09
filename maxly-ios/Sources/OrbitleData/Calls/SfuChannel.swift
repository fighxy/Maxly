import Foundation

/// Служебные каналы данных SFU: `producerCommand` (наши команды) и `producerNotification`
/// (алиасы дорожек, слоты видео и уровни звука). Сервер говорит в них MessagePack; схема
/// кадров — как у Komet (`sfu_data_channel.dart`), кодек свой.
public enum SfuChannel {
    public static let commandLabel = "producerCommand"
    public static let notificationLabel = "producerNotification"

    /// Одно окно видео в раскладке: чьё видео и какого размера нужно.
    public struct LayoutItem: Hashable, Sendable {
        public var trackKey: String
        public var width: Int
        public var height: Int

        public init(trackKey: String, width: Int = 640, height: Int = 360) {
            self.trackKey = trackKey
            self.width = width
            self.height = height
        }
    }

    /// Уведомление канала `producerNotification`.
    public enum Notification: Hashable, Sendable {
        /// Ключи дорожек получили короткие номера (алиасы).
        case aliases([Int: String])
        /// Ключ дорожки → номер видеослота (`video-pat-<слот>`).
        case slots([String: Int])
        /// Ключ дорожки → уровень звука 0…127.
        case levels([String: Int])
    }

    /// Команда `update-display-layout` (код 0): какие видео присылать. Байты повторяют то, что
    /// шлёт Komet: тип, версия, номер, `snapshot`, массив окон или `nil`, завершающий `nil`.
    public static func displayLayout(_ items: [LayoutItem], sequence: Int, snapshot: Bool = true) -> Data {
        var writer = MessagePackWriter()
        writer.int(0)
        writer.int(0)
        writer.int(sequence)
        writer.bool(snapshot)
        if items.isEmpty {
            writer.null()
        } else {
            writer.arrayHeader(items.count * 2)
            for item in items {
                writer.string(item.trackKey)
                writer.int(0)
                writer.null()
                writer.int(item.width)
                writer.int(item.height)
                writer.int(0)
            }
        }
        writer.null()
        return writer.data
    }

    /// Разбирает уведомление; алиасы из прошлых кадров переводят номера в ключи.
    /// `nil` — незнакомый или битый кадр.
    public static func parse(_ data: Data, aliases: [Int: String]) -> Notification? {
        guard let type = data.first else { return nil }
        var reader = MessagePackReader(data.dropFirst())
        do {
            switch type {
            case 1:
                var map: [Int: String] = [:]
                let count = try reader.mapHeader()
                for _ in 0..<count {
                    let key = try reader.string()
                    let alias = try reader.int()
                    map[alias] = key
                }
                return .aliases(map)
            case 2:
                var slots: [String: Int] = [:]
                let count = try reader.arrayHeader()
                for slot in 0..<count {
                    let alias = try reader.int()
                    if let key = aliases[alias] { slots[key] = slot }
                }
                return .slots(slots)
            case 6:
                var levels: [String: Int] = [:]
                let count = try reader.mapHeader()
                for _ in 0..<count {
                    let alias = try reader.int()
                    let level = try reader.int()
                    if let key = aliases[alias] { levels[key] = level }
                }
                return .levels(levels)
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

/// Запись MessagePack: только то, что нужно командам SFU.
struct MessagePackWriter {
    private(set) var data = Data()

    mutating func null() { data.append(0xC0) }

    mutating func bool(_ value: Bool) { data.append(value ? 0xC3 : 0xC2) }

    mutating func int(_ value: Int) {
        switch value {
        case 0..<0x80:
            data.append(UInt8(value))
        case 0x80...0xFF:
            data.append(0xCC)
            data.append(UInt8(value))
        case 0x100...0xFFFF:
            data.append(0xCD)
            append(UInt64(value), bytes: 2)
        case 0x10000...0xFFFF_FFFF:
            data.append(0xCE)
            append(UInt64(value), bytes: 4)
        case 0x1_0000_0000...:
            data.append(0xCF)
            append(UInt64(value), bytes: 8)
        case -32 ..< 0:
            data.append(UInt8(bitPattern: Int8(value)))
        case -128 ..< -32:
            data.append(0xD0)
            data.append(UInt8(bitPattern: Int8(value)))
        case -32768 ..< -128:
            data.append(0xD1)
            append(UInt64(UInt16(bitPattern: Int16(value))), bytes: 2)
        case Int(Int32.min) ..< -32768:
            data.append(0xD2)
            append(UInt64(UInt32(bitPattern: Int32(value))), bytes: 4)
        default:
            data.append(0xD3)
            append(UInt64(bitPattern: Int64(value)), bytes: 8)
        }
    }

    mutating func string(_ value: String) {
        let bytes = Array(value.utf8)
        switch bytes.count {
        case 0..<32:
            data.append(0xA0 | UInt8(bytes.count))
        case 32...0xFF:
            data.append(0xD9)
            data.append(UInt8(bytes.count))
        case 0x100...0xFFFF:
            data.append(0xDA)
            append(UInt64(bytes.count), bytes: 2)
        default:
            data.append(0xDB)
            append(UInt64(bytes.count), bytes: 4)
        }
        data.append(contentsOf: bytes)
    }

    mutating func mapHeader(_ count: Int) {
        switch count {
        case 0..<16:
            data.append(0x80 | UInt8(count))
        case 16...0xFFFF:
            data.append(0xDE)
            append(UInt64(count), bytes: 2)
        default:
            data.append(0xDF)
            append(UInt64(count), bytes: 4)
        }
    }

    mutating func arrayHeader(_ count: Int) {
        switch count {
        case 0..<16:
            data.append(0x90 | UInt8(count))
        case 16...0xFFFF:
            data.append(0xDC)
            append(UInt64(count), bytes: 2)
        default:
            data.append(0xDD)
            append(UInt64(count), bytes: 4)
        }
    }

    private mutating func append(_ value: UInt64, bytes: Int) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}

/// Чтение MessagePack: целые, строки, заголовки массивов и словарей.
struct MessagePackReader {
    struct Malformed: Error {}

    private let bytes: [UInt8]
    private var position = 0

    init<D: Collection>(_ data: D) where D.Element == UInt8 {
        bytes = Array(data)
    }

    mutating func int() throws -> Int {
        let head = try byte()
        switch head {
        case 0x00...0x7F: return Int(head)
        case 0xE0...0xFF: return Int(Int8(bitPattern: head))
        case 0xCC: return Int(try unsigned(1))
        case 0xCD: return Int(try unsigned(2))
        case 0xCE: return Int(try unsigned(4))
        case 0xCF: return Int(truncatingIfNeeded: try unsigned(8))
        case 0xD0: return Int(Int8(truncatingIfNeeded: try unsigned(1)))
        case 0xD1: return Int(Int16(truncatingIfNeeded: try unsigned(2)))
        case 0xD2: return Int(Int32(truncatingIfNeeded: try unsigned(4)))
        case 0xD3: return Int(Int64(bitPattern: try unsigned(8)))
        default: throw Malformed()
        }
    }

    mutating func string() throws -> String {
        let head = try byte()
        let length: Int
        switch head {
        case 0xA0...0xBF: length = Int(head & 0x1F)
        case 0xD9: length = Int(try unsigned(1))
        case 0xDA: length = Int(try unsigned(2))
        case 0xDB: length = Int(try unsigned(4))
        default: throw Malformed()
        }
        guard position + length <= bytes.count else { throw Malformed() }
        defer { position += length }
        return String(decoding: bytes[position ..< position + length], as: UTF8.self)
    }

    mutating func mapHeader() throws -> Int {
        let head = try byte()
        switch head {
        case 0x80...0x8F: return Int(head & 0x0F)
        case 0xDE: return Int(try unsigned(2))
        case 0xDF: return Int(try unsigned(4))
        default: throw Malformed()
        }
    }

    mutating func arrayHeader() throws -> Int {
        let head = try byte()
        switch head {
        case 0x90...0x9F: return Int(head & 0x0F)
        case 0xDC: return Int(try unsigned(2))
        case 0xDD: return Int(try unsigned(4))
        default: throw Malformed()
        }
    }

    private mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw Malformed() }
        defer { position += 1 }
        return bytes[position]
    }

    private mutating func unsigned(_ count: Int) throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<count {
            value = (value << 8) | UInt64(try byte())
        }
        return value
    }
}
