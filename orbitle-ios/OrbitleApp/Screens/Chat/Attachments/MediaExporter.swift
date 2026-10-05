@preconcurrency import AVFoundation
import Foundation
import ImageIO
@preconcurrency import Photos
import UIKit
import UniformTypeIdentifiers
import OrbitleDomain

/// Готовит файлы к отправке: фото в JPEG не больше 2560 px, видео в mp4, файлы копией.
/// Всё кладёт в Caches/Outgoing/<uuid>/: оттуда грузит ядро, а пузырь показывает превью.
enum MediaExporter {
    enum Failure: LocalizedError {
        case unreadable
        case exportFailed(String?)

        var errorDescription: String? {
            switch self {
            case .unreadable: "Не удалось прочитать файл"
            case .exportFailed(let reason): reason ?? "Не удалось подготовить видео"
            }
        }
    }

    static let maxPixels = 2560
    static let jpegQuality = 0.85

    // MARK: Медиатека

    static func draft(for ref: AssetRef) async throws -> AttachmentDraft {
        switch ref.asset.mediaType {
        case .video:
            let avAsset = try await avAsset(for: ref.asset)
            return try await exportVideo(avAsset)
        default:
            let data = try await imageData(for: ref.asset)
            return try writePhoto(data)
        }
    }

    // MARK: Камера

    static func draft(camera image: UIImage) throws -> AttachmentDraft {
        guard let data = image.jpegData(compressionQuality: 0.95) else { throw Failure.unreadable }
        return try writePhoto(data)
    }

    static func draft(cameraVideo url: URL) async throws -> AttachmentDraft {
        try await exportVideo(AVURLAsset(url: url))
    }

    /// Фото из системного выбора (новая история): JPEG не больше 2560 px.
    static func draft(photoData data: Data) throws -> AttachmentDraft {
        try writePhoto(data)
    }

    // MARK: Файлы

    /// Копия файла из «Файлов». Доступ к файлу вне песочницы открыт только на время копии.
    static func draft(file url: URL) throws -> AttachmentDraft {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let target = try makeFolder().appendingPathComponent(name)
        var readError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &readError) { readable in
            do {
                try FileManager.default.copyItem(at: readable, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = readError ?? copyError { throw error }
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
        return AttachmentDraft(kind: .file, path: target.path, fileName: name, size: size)
    }

    // MARK: Внутреннее

    private static func writePhoto(_ data: Data) throws -> AttachmentDraft {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        let target = try makeFolder().appendingPathComponent("image.jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            target as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw Failure.unreadable }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
        return AttachmentDraft(
            kind: .photo, path: target.path, fileName: "image.jpg", size: size,
            width: image.width, height: image.height
        )
    }

    private static func exportVideo(_ asset: AVAsset) async throws -> AttachmentDraft {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw Failure.exportFailed(nil)
        }
        let target = try makeFolder().appendingPathComponent("video.mp4")
        session.shouldOptimizeForNetworkUse = true
        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: target, as: .mp4)
            } catch {
                throw Failure.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = target
            session.outputFileType = .mp4
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                throw Failure.exportFailed(session.error?.localizedDescription)
            }
        }
        let exported = AVURLAsset(url: target)
        let duration = (try? await exported.load(.duration)).map(CMTimeGetSeconds) ?? 0
        var width: Int?
        var height: Int?
        if let track = try? await exported.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let box = CGRect(origin: .zero, size: natural).applying(transform)
            width = Int(abs(box.width).rounded())
            height = Int(abs(box.height).rounded())
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
        return AttachmentDraft(
            kind: .video, path: target.path, fileName: "video.mp4", size: size,
            width: width, height: height,
            durationMs: duration.isFinite ? Int64((duration * 1000).rounded()) : 0
        )
    }

    private static func imageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? Failure.unreadable)
                }
            }
        }
    }

    private static func avAsset(for asset: PHAsset) async throws -> AVAsset {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? Failure.unreadable)
                }
            }
        }
    }

    private static func makeFolder() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = caches
            .appendingPathComponent("Outgoing", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
