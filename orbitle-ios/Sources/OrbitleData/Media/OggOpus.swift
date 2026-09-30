import Foundation

/// Голосовые Max приходят файлами Ogg с Opus. Контейнер Ogg системные плееры iOS не открывают,
/// а Opus в контейнере CAF играет `AVAudioPlayer`. `OggOpus` перекладывает пакеты Opus из Ogg
/// в CAF без перекодирования (RFC 7845 для Ogg Opus, Apple Core Audio Format для CAF).
public enum OggOpus {
    public enum Failure: Error, Equatable {
        case notOgg
        case notOpus
        case noAudio
        case truncated
    }

    /// Файл начинается с подписи страницы Ogg.
    public static func isOgg(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x4F, 0x67, 0x67, 0x53])
    }

    /// CAF с теми же пакетами Opus.
    public static func caf(fromOgg data: Data) throws(Failure) -> Data {
        let stream = try parse(data)
        return CAFWriter.opus(stream)
    }

    /// Первый логический поток Ogg Opus: заголовок и пакеты звука.
    struct Stream: Equatable {
        var channels: Int
        var preSkip: Int
        var packets: [Data]
        /// Отсчётов 48 кГц в каждом пакете.
        var frames: [Int]
        /// Позиция последней страницы (отсчёты с учётом `preSkip`), `nil` если её нет.
        var finalGranule: Int64?
    }

    static func parse(_ data: Data) throws(Failure) -> Stream {
        guard isOgg(data) else { throw .notOgg }
        let bytes = [UInt8](data)
        var offset = 0
        var serial: UInt32?
        var partial = Data()
        var packets: [Data] = []
        var granule: Int64?
        while offset + 27 <= bytes.count {
            guard bytes[offset] == 0x4F, bytes[offset + 1] == 0x67, bytes[offset + 2] == 0x67, bytes[offset + 3] == 0x53 else {
                throw .truncated
            }
            let pageGranule = Int64(bitPattern: littleEndian(bytes, offset + 6, count: 8))
            let pageSerial = UInt32(truncatingIfNeeded: littleEndian(bytes, offset + 14, count: 4))
            let segments = Int(bytes[offset + 26])
            let tableStart = offset + 27
            guard tableStart + segments <= bytes.count else { throw .truncated }
            let lacing = bytes[tableStart..<(tableStart + segments)]
            var cursor = tableStart + segments
            let body = lacing.reduce(0) { $0 + Int($1) }
            guard cursor + body <= bytes.count else { throw .truncated }
            if serial == nil { serial = pageSerial }
            // Другие логические потоки (если есть) пропускаем.
            if pageSerial == serial {
                for value in lacing {
                    let size = Int(value)
                    partial.append(contentsOf: bytes[cursor..<(cursor + size)])
                    cursor += size
                    if value < 255 {
                        packets.append(partial)
                        partial = Data()
                    }
                }
                if pageGranule >= 0 { granule = pageGranule }
            }
            offset = tableStart + segments + body
        }
        guard let head = packets.first, head.count >= 19, head.prefix(8).elementsEqual(Array("OpusHead".utf8)) else {
            throw .notOpus
        }
        let headBytes = [UInt8](head)
        let channels = max(1, Int(headBytes[9]))
        let preSkip = Int(littleEndian(headBytes, 10, count: 2))
        // Второй пакет — OpusTags, дальше звук.
        var audio = Array(packets.dropFirst())
        if let tags = audio.first, tags.prefix(8).elementsEqual(Array("OpusTags".utf8)) {
            audio.removeFirst()
        }
        audio.removeAll { $0.isEmpty }
        guard !audio.isEmpty else { throw .noAudio }
        return Stream(
            channels: channels,
            preSkip: preSkip,
            packets: audio,
            frames: audio.map(frameCount),
            finalGranule: granule
        )
    }

    /// Отсчётов 48 кГц в пакете по байту TOC (RFC 6716, раздел 3.1).
    static func frameCount(_ packet: Data) -> Int {
        guard let toc = packet.first else { return 0 }
        let config = Int(toc >> 3)
        let perFrame: Int
        switch config {
        case 0...11: perFrame = [480, 960, 1920, 2880][config % 4]
        case 12...15: perFrame = [480, 960][config % 2]
        default: perFrame = [120, 240, 480, 960][config % 4]
        }
        let count: Int
        switch toc & 0x3 {
        case 0: count = 1
        case 1, 2: count = 2
        default:
            count = packet.count > 1 ? Int(packet[packet.startIndex + 1] & 0x3F) : 0
        }
        return perFrame * count
    }

    private static func littleEndian(_ bytes: [UInt8], _ start: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in (0..<count).reversed() {
            value = (value << 8) | UInt64(bytes[start + index])
        }
        return value
    }
}

/// Запись CAF (все числа big-endian).
enum CAFWriter {
    static func opus(_ stream: OggOpus.Stream) -> Data {
        var file = Data()
        file.append(contentsOf: Array("caff".utf8))
        file.append(be: UInt16(1))
        file.append(be: UInt16(0))

        let constant = Set(stream.frames).count == 1 ? stream.frames[0] : 0
        // desc: формат потока.
        var desc = Data()
        desc.append(be: Double(48_000).bitPattern)
        desc.append(contentsOf: Array("opus".utf8))
        desc.append(be: UInt32(0)) // mFormatFlags
        desc.append(be: UInt32(0)) // mBytesPerPacket: переменный
        desc.append(be: UInt32(constant)) // mFramesPerPacket: 0 — у каждого пакета свой
        desc.append(be: UInt32(stream.channels))
        desc.append(be: UInt32(0)) // mBitsPerChannel
        file.append(chunk: "desc", desc)

        // pakt: размеры пакетов (и число отсчётов, если оно меняется).
        let total = stream.frames.reduce(0, +)
        let priming = min(stream.preSkip, total)
        var valid = total - priming
        if let granule = stream.finalGranule, granule > Int64(priming), granule <= Int64(total) {
            valid = Int(granule) - priming
        }
        let remainder = max(0, total - priming - valid)
        var pakt = Data()
        pakt.append(be: UInt64(stream.packets.count))
        pakt.append(be: UInt64(valid))
        pakt.append(be: UInt32(priming))
        pakt.append(be: UInt32(remainder))
        for (packet, frames) in zip(stream.packets, stream.frames) {
            pakt.append(varint: UInt64(packet.count))
            if constant == 0 { pakt.append(varint: UInt64(frames)) }
        }
        file.append(chunk: "pakt", pakt)

        // data: счётчик правок и пакеты подряд.
        var body = Data()
        body.append(be: UInt32(0))
        for packet in stream.packets { body.append(packet) }
        file.append(chunk: "data", body)
        return file
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(be value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func append(chunk type: String, _ body: Data) {
        append(contentsOf: Array(type.utf8))
        append(be: Int64(body.count))
        append(body)
    }

    /// Целое переменной длины CAF: по 7 бит, старшие группы первыми, у всех, кроме последней, бит 0x80.
    mutating func append(varint value: UInt64) {
        var groups: [UInt8] = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            groups.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        append(contentsOf: groups.reversed())
    }
}
