import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlData

/// Запрос, на который сервер так и не отвечает.
final class StallingProtocol: URLProtocol {
    static let started = Counter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.started.increment() }
    override func stopLoading() {}
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

@Suite("Медиа: отмена")
struct MediaCancellationTests {
    @Test("Отмена превью обрывает зависший запрос, файла в кэше нет, ошибка не показывается")
    func cancelStalledPreview() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StallingProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appending(path: "orbitl-media-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = MediaRepositoryImpl(http: URLSessionClient(configuration: configuration), directory: directory)
        let item = MediaItem(id: "photo-1", type: .image, url: URL(string: "https://media.invalid/photo-1")!, size: 10)

        let before = StallingProtocol.started.value
        let preview = Task { await failure { _ = try await media.preview(for: item) } }
        #expect(await eventually { StallingProtocol.started.value > before })
        preview.cancel()

        #expect(await preview.value == .cancelled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
