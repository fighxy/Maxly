import Foundation
import Testing
@testable import OrbitleUI

private actor ImageLoadGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private(set) var calls = 0
    let bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    func load(_ url: URL) async -> Data? {
        calls += 1
        if !open { await withCheckedContinuation { waiters.append($0) } }
        return bytes
    }
    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
private func cacheEventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

@Suite("Асинхронный кэш изображений")
@MainActor
struct ImagePipelineTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATElEQVR4nO3PUQkAIBTAwJfFtLbWEH4cwmABbnP2+rrhgga0oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhACxrQgga0oAEtaEALHrvkHEjEeeV5twAAAABJRU5ErkJggg==")!

    @Test("Один источник байтов для одновременно запрошенных размеров")
    func sharedBytes() async throws {
        let gate = ImageLoadGate(bytes: png)
        let pipeline = ImagePipeline(dataLoader: { await gate.load($0) })
        let url = try #require(URL(string: "https://example.invalid/shared.png"))
        let small = Task { await pipeline.image(for: url, maxPixel: 16) }
        let large = Task { await pipeline.image(for: url, maxPixel: 32) }
        #expect(await cacheEventually { await pipeline.pendingImageCount == 2 })
        await gate.release()
        let first = try #require(await small.value)
        let second = try #require(await large.value)
        #expect(await gate.calls == 1)
        #expect(first.image.size.width == 16)
        #expect(second.image.size.width == 32)
        #expect(pipeline.cached(url, maxPixel: 16) === first)
        #expect(pipeline.cached(url, maxPixel: 32) === second)
    }

    @Test("Очистка не позволяет старой загрузке заполнить новое поколение")
    func clearDuringLoad() async throws {
        let gate = ImageLoadGate(bytes: png)
        let pipeline = ImagePipeline(dataLoader: { await gate.load($0) })
        let url = try #require(URL(string: "https://example.invalid/clear.png"))
        let old = Task { await pipeline.image(for: url, maxPixel: 32) }
        #expect(await cacheEventually { await gate.calls == 1 })
        await pipeline.removeAll()
        let fresh = Task { await pipeline.image(for: url, maxPixel: 32) }
        #expect(await cacheEventually { await gate.calls == 2 })
        await gate.release()
        #expect(await old.value == nil)
        let image = try #require(await fresh.value)
        #expect(pipeline.cached(url, maxPixel: 32) === image)
    }

    @Test("Локальная картинка читается асинхронно и остаётся в памяти после удаления файла")
    func localFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = ImagePipeline(memoryLimit: 4, diskCapacity: 0)
        let image = try #require(await pipeline.image(for: url, maxPixel: 32))
        try FileManager.default.removeItem(at: url)
        #expect(await pipeline.image(for: url, maxPixel: 32) === image)
        await pipeline.removeAll()
        #expect(pipeline.cached(url, maxPixel: 32) == nil)
        #expect(await pipeline.image(for: url, maxPixel: 32) == nil)
    }
}
