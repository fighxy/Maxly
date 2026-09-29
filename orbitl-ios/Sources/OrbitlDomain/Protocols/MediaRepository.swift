import Foundation

/// Медиа: превью, скачивание с прогрессом и отменой, дисковый кэш.
// TODO: architecture.md, раздел «Медиа».
public protocol MediaRepository: Sendable {
    func preview(for item: MediaItem) async throws(OrbitlError) -> URL
    func download(_ item: MediaItem) -> AsyncThrowingStream<Double, Error>
}
