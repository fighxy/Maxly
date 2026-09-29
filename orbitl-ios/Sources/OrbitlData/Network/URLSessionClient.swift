import Foundation

/// HTTP для медиа. Протокол Max через этот клиент не ходит.
public actor URLSessionClient {
    public init() {}

    /// Скачивает файл на диск и сообщает долю от 0 до 1.
    public func download(from url: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let loader = FileDownload(destination: destination, progress: onProgress)
        try await loader.run(url)
    }
}

/// `URLSessionDownloadDelegate` пишет во временный файл и переносит его в кэш.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func run(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
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
            finish(session, .failure(URLError(.badServerResponse)))
            return
        }
        do {
            let folder = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(session, .success(()))
        } catch {
            finish(session, .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(session, .failure(error))
        }
    }

    private func finish(_ session: URLSession, _ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        session.invalidateAndCancel()
        self.session = nil
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
