import Testing
@testable import MaxlyPresentation

@Suite("Автовоспроизведение GIF")
struct GifAutoplayPolicyTests {
    @Test("«Всегда» играет в любой сети")
    func always() {
        for network in [NetworkKind.wifi, .wired, .cellular, .other, .offline] {
            #expect(GifAutoplayPolicy.allows(.always, network: network))
        }
    }

    @Test("«Никогда» не играет даже в Wi‑Fi")
    func never() {
        #expect(!GifAutoplayPolicy.allows(.never, network: .wifi))
        #expect(!GifAutoplayPolicy.allows(.never, network: .cellular))
    }

    @Test("«Только Wi‑Fi»: Wi‑Fi и кабель да, сотовая и экономия трафика нет")
    func wifiOnly() {
        #expect(GifAutoplayPolicy.allows(.wifiOnly, network: .wifi))
        #expect(GifAutoplayPolicy.allows(.wifiOnly, network: .wired))
        #expect(!GifAutoplayPolicy.allows(.wifiOnly, network: .cellular))
        #expect(!GifAutoplayPolicy.allows(.wifiOnly, network: .other))
        #expect(!GifAutoplayPolicy.allows(.wifiOnly, network: .offline))
        #expect(!GifAutoplayPolicy.allows(.wifiOnly, network: .wifi, constrained: true))
    }

    @Test("Плитка играет только на экране и только с роликом")
    func tile() {
        #expect(GifAutoplayPolicy.shouldPlay(allowed: true, hasVideo: true, visible: true))
        #expect(!GifAutoplayPolicy.shouldPlay(allowed: true, hasVideo: true, visible: false))
        #expect(!GifAutoplayPolicy.shouldPlay(allowed: true, hasVideo: false, visible: true))
        #expect(!GifAutoplayPolicy.shouldPlay(allowed: false, hasVideo: true, visible: true))
    }

    @Test("Сохранённое значение читается, мусор даёт значение по умолчанию")
    func stored() {
        #expect(GifAutoplayMode(stored: "wifiOnly") == .wifiOnly)
        #expect(GifAutoplayMode(stored: "never") == .never)
        #expect(GifAutoplayMode(stored: "junk") == .always)
        #expect(GifAutoplayMode(stored: nil) == .always)
    }
}
