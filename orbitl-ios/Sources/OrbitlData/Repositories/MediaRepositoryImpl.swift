import Foundation
import OrbitlDomain

/// Дисковый кэш медиа. Старые файлы вытесняются по дате использования.
public actor MediaRepositoryImpl: MediaRepository {
    public static let defaultByteLimit: Int64 = 200 * 1024 * 1024

    private let http: URLSessionClient
    private let directory: URL
    private let byteLimit: Int64

    public init(http: URLSessionClient, directory: URL, byteLimit: Int64 = defaultByteLimit) {
        self.http = http
        self.directory = directory
        self.byteLimit = byteLimit
    }

    public static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "OrbitlMedia", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func preview(for item: MediaItem) async throws(OrbitlError) -> URL {
        if let cached = cached(item) {
            touch(cached)
            return cached
        }
        do {
            return try await fetch(item) { _ in }
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError {
            throw error.code == .cancelled ? .cancelled : .networkUnavailable
        } catch {
            throw .storageError
        }
    }

    public nonisolated func download(_ item: MediaItem) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if await self.cached(item) != nil {
                        continuation.yield(1)
                        continuation.finish()
                        return
                    }
                    _ = try await self.fetch(item) { continuation.yield($0) }
                    continuation.yield(1)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func clearCache() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func cached(_ item: MediaItem) -> URL? {
        let url = destination(for: item)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func fetch(_ item: MediaItem, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dest = destination(for: item)
        try await http.download(from: item.url, to: dest, onProgress: progress)
        try MediaCache.evict(directory: directory, limit: byteLimit)
        return dest
    }

    private func destination(for item: MediaItem) -> URL {
        let name = item.id.filter { $0.isLetter || $0.isNumber }
        return directory.appending(path: name.isEmpty ? "file" : name)
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}

enum MediaCache {
    /// Удаляет самые давно использованные файлы, пока каталог не влезет в `limit`.
    static func evict(directory: URL, limit: Int64) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        var sized = try files.map { url -> (URL, Int64, Date) in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = sized.reduce(Int64(0)) { $0 + $1.1 }
        while total > limit, let oldest = sized.first {
            try FileManager.default.removeItem(at: oldest.0)
            total -= oldest.1
            sized.removeFirst()
        }
    }
}
