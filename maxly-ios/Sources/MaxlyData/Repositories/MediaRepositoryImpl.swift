import Foundation
import MaxlyDomain

/// Дисковый кэш медиа: файлы лежат по папкам категорий (`StorageLayout`). Сроки хранения
/// и предел размера применяет `DeviceStorage`: репозиторий зовёт `onStored` после загрузки.
public actor MediaRepositoryImpl: MediaRepository {
    private let http: URLSessionClient
    private let layout: StorageLayout
    private let onStored: @Sendable () async -> Void

    public init(http: URLSessionClient, layout: StorageLayout, onStored: @escaping @Sendable () async -> Void = {}) {
        self.http = http
        self.layout = layout
        self.onStored = onStored
    }

    public init(http: URLSessionClient, directory: URL) {
        self.init(http: http, layout: StorageLayout(root: directory))
    }

    public func preview(for item: MediaItem) async throws(MaxlyError) -> URL {
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
        guard let files = try? FileManager.default.contentsOfDirectory(at: layout.root, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func cached(_ item: MediaItem) -> URL? {
        let url = destination(for: item)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        // Прежняя раскладка: все файлы прямо в корне. Найденный файл переезжает в свою папку.
        let legacy = layout.root.appending(path: url.lastPathComponent)
        guard FileManager.default.fileExists(atPath: legacy.path),
              (try? layout.prepared(item.type.storageCategory)) != nil,
              (try? FileManager.default.moveItem(at: legacy, to: url)) != nil else { return nil }
        return url
    }

    private func fetch(_ item: MediaItem, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        _ = try layout.prepared(item.type.storageCategory)
        let dest = destination(for: item)
        try await http.download(from: item.url, to: dest, onProgress: progress)
        await onStored()
        return dest
    }

    private func destination(for item: MediaItem) -> URL {
        let name = item.id.filter { $0.isLetter || $0.isNumber }
        var url = layout.directory(item.type.storageCategory).appending(path: name.isEmpty ? "file" : name)
        let ext = item.url.pathExtension
        if !ext.isEmpty, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
            url.appendPathExtension(ext)
        } else if item.type == .video || item.type == .videoNote {
            // Адреса роликов CDN Max без расширения: AVPlayer не узнаёт формат файла без него
            // (AVFoundationErrorDomain −11828) и кружок из кэша не играет.
            url.appendPathExtension("mp4")
        }
        return url
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }
}
