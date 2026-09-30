import Foundation

/// Упаковка пакетов Opus в файл Ogg Opus (RFC 7845) для отправки голосового.
///
/// Сервер Max доводит до готовности только Ogg/Opus: так записывает Komet, а Opus от
/// системного кодера без контейнера Ogg остаётся «не готов». Пакеты кодирует системный
/// кодер (`kAudioFormatOpus`), здесь они только раскладываются по страницам Ogg:
/// заголовок `OpusHead`, теги `OpusTags` и звук, страницы примерно по секунде.
public struct OggOpusWriter: Sendable {
    public let channels: Int
    public let preSkip: Int
    private let serial: UInt32
    private var output = Data()
    private var sequence: UInt32 = 0
    private var granule: Int64 = 0
    private var pending: [Data] = []
    private var pendingSegments = 0
    private var pageStart: Int64 = 0
    private var finished = false

    /// Отсчётов 48 кГц на странице, после которых она закрывается.
    private static let pageFrames: Int64 = 48_000
    /// Сколько уже записано отсчётов 48 кГц (с учётом `preSkip`).
    public var frames: Int64 { granule }

    public init(channels: Int = 1, preSkip: Int = 312, serial: UInt32 = UInt32.random(in: 1...UInt32.max)) {
        self.channels = max(1, min(2, channels))
        self.preSkip = max(0, min(Int(UInt16.max), preSkip))
        self.serial = serial
        writePage([Self.head(channels: self.channels, preSkip: self.preSkip)], granule: 0, flags: 0x02)
        writePage([Self.tags()], granule: 0, flags: 0)
    }

    /// Добавить пакет Opus. `frames` — отсчётов 48 кГц в нём, по умолчанию из байта TOC.
    public mutating func append(packet: Data, frames: Int? = nil) {
        guard !finished, !packet.isEmpty else { return }
        let segments = packet.count / 255 + 1
        if pendingSegments + segments > 255 { flush(flags: 0) }
        pending.append(packet)
        pendingSegments += segments
        granule += Int64(frames ?? OggOpus.frameCount(packet))
        if granule - pageStart >= Self.pageFrames { flush(flags: 0) }
    }

    /// Закрыть поток: последняя страница с флагом конца. Возвращает весь файл.
    public mutating func finish() -> Data {
        guard !finished else { return output }
        if pending.isEmpty {
            // Флаг конца нужен на странице: пустая страница с ним допустима.
            writePage([], granule: granule, flags: 0x04)
        } else {
            flush(flags: 0x04)
        }
        finished = true
        return output
    }

    private mutating func flush(flags: UInt8) {
        guard !pending.isEmpty else { return }
        writePage(pending, granule: granule, flags: flags)
        pending = []
        pendingSegments = 0
        pageStart = granule
    }

    private mutating func writePage(_ packets: [Data], granule: Int64, flags: UInt8) {
        var lacing: [UInt8] = []
        var body = Data()
        for packet in packets {
            var left = packet.count
            while left >= 255 {
                lacing.append(255)
                left -= 255
            }
            lacing.append(UInt8(left))
            body.append(packet)
        }
        var page = Data()
        page.append(contentsOf: Array("OggS".utf8))
        page.append(0) // версия
        page.append(flags)
        page.appendLittle(UInt64(bitPattern: granule))
        page.appendLittle(serial)
        page.appendLittle(sequence)
        let crcOffset = page.count
        page.appendLittle(UInt32(0))
        page.append(UInt8(lacing.count))
        page.append(contentsOf: lacing)
        page.append(body)
        let crc = Self.crc(page)
        page.replaceSubrange(crcOffset..<(crcOffset + 4), with: withUnsafeBytes(of: crc.littleEndian) { Data($0) })
        output.append(page)
        sequence += 1
    }

    static func head(channels: Int, preSkip: Int) -> Data {
        var data = Data(Array("OpusHead".utf8))
        data.append(1) // версия
        data.append(UInt8(channels))
        data.appendLittle(UInt16(preSkip))
        data.appendLittle(UInt32(48_000)) // исходная частота
        data.appendLittle(UInt16(0)) // усиление
        data.append(0) // схема каналов: моно или стерео
        return data
    }

    static func tags() -> Data {
        let vendor = Array("Orbitle".utf8)
        var data = Data(Array("OpusTags".utf8))
        data.appendLittle(UInt32(vendor.count))
        data.append(contentsOf: vendor)
        data.appendLittle(UInt32(0)) // комментариев нет
        return data
    }

    /// CRC-32 Ogg: многочлен 0x04C11DB7, без отражения, начальное значение 0.
    static func crc(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            crc = (crc << 8) ^ table[Int(((crc >> 24) & 0xFF) ^ UInt32(byte))]
        }
        return crc
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index) << 24
        for _ in 0..<8 {
            value = value & 0x8000_0000 != 0 ? (value << 1) ^ 0x04C1_1DB7 : value << 1
        }
        return value
    }
}

private extension Data {
    mutating func appendLittle<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
