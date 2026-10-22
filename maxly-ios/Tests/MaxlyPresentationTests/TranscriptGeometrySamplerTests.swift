import Testing
@testable import MaxlyPresentation

@Suite("Сэмплер геометрии ленты")
struct TranscriptGeometrySamplerTests {
    @Test("Первый вызов и force проходят, частые — нет")
    func throttles() {
        let sampler = TranscriptGeometrySampler(minIntervalMs: 16)
        #expect(sampler.shouldFire(nowNs: 1_000))
        #expect(!sampler.shouldFire(nowNs: 1_000 + 1_000_000))
        #expect(sampler.shouldFire(nowNs: 1_000 + 16_000_000))
        #expect(sampler.shouldFire(nowNs: 1_000 + 16_000_001, force: true))
    }
}
