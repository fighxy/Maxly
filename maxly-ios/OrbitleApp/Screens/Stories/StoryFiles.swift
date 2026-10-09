import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import OrbitleDomain

/// Выбранное фото или видео — в файл для новой истории: фото в JPEG, видео в MP4
/// (`MediaExporter`, как вложения чата). Ядро грузит историю по пути к файлу.
enum StoryFiles {
    static func prepare(_ item: PhotosPickerItem) async -> OutgoingStory? {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        do {
            if isVideo {
                guard let movie = try await item.loadTransferable(type: StoryMovie.self) else { return nil }
                let draft = try await MediaExporter.draft(cameraVideo: movie.url)
                try? FileManager.default.removeItem(at: movie.url.deletingLastPathComponent())
                return OutgoingStory(
                    fileURL: URL(fileURLWithPath: draft.path),
                    isVideo: true,
                    duration: draft.durationMs > 0 ? Double(draft.durationMs) / 1000 : nil
                )
            }
            guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
            let draft = try MediaExporter.draft(photoData: data)
            return OutgoingStory(fileURL: URL(fileURLWithPath: draft.path), isVideo: false)
        } catch {
            Log.warning(.media, "Файл для истории не подготовлен: \(error)")
            return nil
        }
    }
}

/// Видео из системного выбора: копия во временной папке, пока его не перекодируют в MP4.
struct StoryMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("story-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = received.file.lastPathComponent.isEmpty ? "story.mov" : received.file.lastPathComponent
            let copy = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return StoryMovie(url: copy)
        }
    }
}
