import Foundation

/// HTTP для медиа. Протокол Max через этот клиент не ходит.
public actor URLSessionClient {
    private let configuration: URLSessionConfiguration

    /// - Parameter configuration: тесты подставляют свой `URLProtocol`.
    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
    }

    /// Скачивает файл на диск и сообщает долю от 0 до 1.
    /// Отмена задачи обрывает запрос и бросает `CancellationError`.
    public func download(from url: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let loader = FileDownload(configuration: configuration, destination: destination, progress: onProgress)
        try await loader.run(url)
    }
}

/// `URLSessionDownloadDelegate` пишет во временный файл и переносит его в кэш.
///
/// Колбэки сессии, отмена задачи и запуск приходят с разных потоков, поэтому состояние
/// под замком, а завершение срабатывает ровно один раз.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    init(configuration: URLSessionConfiguration, destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.configuration = configuration
        self.destination = destination
        self.progress = progress
    }

    func run(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                guard !finished else {
                    // Задачу отменили ещё до запуска запроса.
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                lock.unlock()
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.99))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        do {
            let folder = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
