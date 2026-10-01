import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OrbitleDomain
import OrbitlePresentation

/// Сохранение в «Фото» через PhotoKit.
///
/// Нужен только доступ «добавлять» (`NSPhotoLibraryAddUsageDescription`): медиатеку
/// Orbitle при этом не читает. Картинки в форматах, которые «Фото» не принимает (WebP с CDN
/// Max), перекладываются в JPEG; видео сохраняется как есть.
struct PhotoLibrarySaver: GallerySaving {
    func save(_ files: [SavedFile]) async throws(OrbitleError) {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            Log.warning(.media, "Нет доступа к «Фото» для сохранения: \(status.rawValue)")
            throw .rejected("Нет доступа к «Фото». Разрешите в Настройках → Orbitle → Фото")
        }
        let prepared = files.map(Self.prepared)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for file in prepared {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = file.name
                    request.addResource(with: file.kind == .video ? .video : .photo, fileURL: file.url, options: options)
                }
            }
            Log.info(.media, "Сохранено в «Фото»: \(files.count)")
        } catch {
            Log.warning(.media, "Не сохранилось в «Фото»: \(error)")
            throw .rejected("Не удалось сохранить в «Фото»")
        }
    }

    /// «Фото» принимает JPEG, HEIC, PNG и GIF; остальное (WebP, AVIF) — копия в JPEG.
    private static func prepared(_ file: SavedFile) -> SavedFile {
        guard file.kind == .image,
              let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String? else { return file }
        let accepted: [UTType] = [.jpeg, .heic, .heif, .png, .gif]
        if let utType = UTType(type), accepted.contains(where: { utType.conforms(to: $0) }) { return file }
        guard let image = UIImage(contentsOfFile: file.url.path), let data = image.jpegData(compressionQuality: 0.95) else { return file }
        let name = (file.name as NSString).deletingPathExtension + ".jpg"
        let target = file.url.deletingLastPathComponent().appending(path: name)
        do {
            try data.write(to: target, options: .atomic)
            return SavedFile(url: target, name: name, kind: .image)
        } catch {
            return file
        }
    }
}

/// Системное окно «Сохранить в Файлы»: пользователь выбирает папку, файлы копируются туда.
struct FileExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    /// `true` — файлы записаны, `false` — окно закрыли без сохранения.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onFinish: (Bool) -> Void
        private var finished = false

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(false)
        }

        private func finish(_ saved: Bool) {
            guard !finished else { return }
            finished = true
            onFinish(saved)
        }
    }
}

extension View {
    /// Окно «Сохранить в Файлы» для экспорта модели чата. Чат и просмотр фото держат
    /// каждый своё окно (`fromViewer`): под открытым просмотром чат окно показать не может.
    func fileExportSheet(_ model: ChatViewModel, fromViewer: Bool) -> some View {
        sheet(item: Binding(
            get: { model.fileExport.flatMap { $0.fromViewer == fromViewer ? $0 : nil } },
            set: { if $0 == nil, model.fileExport?.fromViewer == fromViewer { model.finishFileExport(saved: false) } }
        )) { export in
            FileExportPicker(urls: export.files.map(\.url)) { saved in
                model.finishFileExport(saved: saved)
            }
            .ignoresSafeArea()
        }
    }
}
