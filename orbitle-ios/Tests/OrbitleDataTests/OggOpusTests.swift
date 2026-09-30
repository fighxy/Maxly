import Foundation
import Testing
@testable import OrbitleData

@Suite("Голосовые: Ogg Opus в CAF")
struct OggOpusTests {
    /// Страница Ogg без контрольной суммы: разбор её не проверяет.
    private func page(_ packets: [Data], granule: Int64, serial: UInt32 = 7, continued: Bool = false) -> Data {
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
        var data = Data("OggS".utf8)
        data.append(0)
        data.append(continued ? 1 : 0)
        withUnsafeBytes(of: granule.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: serial.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // номер страницы и CRC
        data.append(UInt8(lacing.count))
        data.append(contentsOf: lacing)
        data.append(body)
        return data
    }

    private func head(channels: UInt8 = 1, preSkip: UInt16 = 312) -> Data {
        var data = Data("OpusHead".utf8)
        data.append(1)
        data.append(channels)
        withUnsafeBytes(of: preSkip.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(48_000).littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0, 0, 0])
        return data
    }

    /// Пакет CELT 20 мс (config 31, один кадр): 960 отсчётов.
    private func packet(_ size: Int) -> Data {
        Data([0xF8] + Array(repeating: UInt8(size % 200), count: size - 1))
    }

    private func sample() -> Data {
        var file = page([head()], granule: 0)
        file.append(page([Data("OpusTags".utf8) + Data(repeating: 0, count: 8)], granule: 0))
        file.append(page([packet(40), packet(300), packet(60)], granule: 2_000))
        return file
    }

    @Test("Подпись Ogg узнаётся, чужой файл нет")
    func signature() {
        #expect(OggOpus.isOgg(sample()))
        #expect(!OggOpus.isOgg(Data("ftypM4A ".utf8)))
        #expect(throws: OggOpus.Failure.notOgg) { try OggOpus.caf(fromOgg: Data("ID3...".utf8)) }
    }

    @Test("Заголовок, теги и пакеты, в том числе длиннее 255 байт")
    func parse() throws {
        let stream = try OggOpus.parse(sample())
        #expect(stream.channels == 1)
        #expect(stream.preSkip == 312)
        #expect(stream.packets.map(\.count) == [40, 300, 60])
        #expect(stream.frames == [960, 960, 960])
        #expect(stream.finalGranule == 2_000)
    }

    @Test("Длительность пакета по байту TOC")
    func frames() {
        #expect(OggOpus.frameCount(Data([0x08])) == 960) // SILK 20 мс
        #expect(OggOpus.frameCount(Data([0x18])) == 2880) // SILK 60 мс
        #expect(OggOpus.frameCount(Data([0xF9])) == 1920) // CELT 20 мс, два кадра
        #expect(OggOpus.frameCount(Data([0xFB, 0x03])) == 2880) // CELT 20 мс, три кадра
        #expect(OggOpus.frameCount(Data()) == 0)
    }

    @Test("CAF: desc, pakt с размерами и data с пакетами подряд")
    func caf() throws {
        let caf = try OggOpus.caf(fromOgg: sample())
        let bytes = [UInt8](caf)
        #expect(Array(bytes[0..<4]) == Array("caff".utf8))
        #expect(Array(bytes[8..<12]) == Array("desc".utf8))
        #expect(Array(bytes[28..<32]) == Array("opus".utf8))
        // mFramesPerPacket = 960, один канал.
        #expect(Array(bytes[40..<44]) == [0, 0, 0x03, 0xC0])
        #expect(Array(bytes[44..<48]) == [0, 0, 0, 1])
        let pakt = 52
        #expect(Array(bytes[pakt..<(pakt + 4)]) == Array("pakt".utf8))
        let p = pakt + 12
        #expect(Array(bytes[p..<(p + 8)]) == [0, 0, 0, 0, 0, 0, 0, 3])
        // 2000 - 312 = 1688 действительных отсчётов, 312 на разгон, 2880 - 2000 = 880 в хвосте.
        #expect(Array(bytes[(p + 8)..<(p + 16)]) == [0, 0, 0, 0, 0, 0, 0x06, 0x98])
        #expect(Array(bytes[(p + 16)..<(p + 20)]) == [0, 0, 0x01, 0x38])
        #expect(Array(bytes[(p + 20)..<(p + 24)]) == [0, 0, 0x03, 0x70])
        // 40, 300 (0x82 0x2C), 60.
        #expect(Array(bytes[(p + 24)..<(p + 28)]) == [40, 0x82, 0x2C, 60])
        let data = p + 28
        #expect(Array(bytes[data..<(data + 4)]) == Array("data".utf8))
        #expect(caf.count == data + 12 + 4 + 400)
    }

    @Test("Без звука и без заголовка Opus — ошибка")
    func failures() {
        #expect(throws: OggOpus.Failure.noAudio) { try OggOpus.caf(fromOgg: page([head()], granule: 0)) }
        #expect(throws: OggOpus.Failure.notOpus) { try OggOpus.caf(fromOgg: page([Data("vorbis-head-xxxxxxxx".utf8)], granule: 0)) }
    }
}
