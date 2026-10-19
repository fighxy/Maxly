import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MaxlyDomain
import MaxlyPresentation

/// Сохранить фото профиля или поделиться им: оригинал качается во временный файл, потом
/// уходит в «Фото» (только добавление, `PhotoLibrarySaver`), в «Файлы» или в окно «Поделиться».
@MainActor
@Observable
final class ProfilePhotoSaver {
    /// Окно «Поделиться» или «Сохранить в Файлы» с готовым файлом.
    struct Export: Identifiable {
        let id = UUID()
        let file: URL
        let share: Bool
    }

    private(set) var isSaving = false
    /// Итог («Фото сохранено в «Фото»») — капсула внизу просмотра.
    private(set) var notice: String?
    var export: Export?
    private var noticeTask: Task<Void, Never>?

    func save(_ url: URL?, title: String, to target: SaveTarget) {
        guard let url, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let file = await Self.download(url, title: title) else {
                show("Не удалось загрузить фото")
                return
            }
            switch target {
            case .photos:
                do throws(MaxlyError) {
                    try await PhotoLibrarySaver().save([SavedFile(url: file, name: file.lastPathComponent, kind: .image)])
                    show("Фото сохранено в «Фото»")
                } catch {
                    if case .rejected(let text) = error { show(text) } else { show("Не удалось сохранить в «Фото»") }
                }
            case .files:
                export = Export(file: file, share: false)
            case .share:
                export = Export(file: file, share: true)
            }
        }
    }

    /// «Сохранено в «Файлы»» после окна экспорта; закрыли без сохранения — молча.
    func finishExport(saved: Bool, share: Bool) {
        export = nil
        if saved && !share { show("Сохранено в «Файлы»") }
    }

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }

    /// Оригинал во временной папке под понятным именем. JPEG и PNG остаются как пришли,
    /// остальное (WebP и прочее, что «Фото» может не принять) перекодируется в JPEG.
    nonisolated private static func download(_ url: URL, title: String) async -> URL? {
        let data: Data
        let mime: String?
        if url.isFileURL {
            guard let local = try? Data(contentsOf: url) else { return nil }
            data = local
            mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        } else {
            guard let (remote, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                Log.warning(.media, "Фото профиля не скачалось")
                return nil
            }
            data = remote
            mime = response.mimeType
        }
        let body: Data
        let ext: String
        switch (mime ?? "").lowercased() {
        case "image/jpeg", "image/jpg":
            body = data
            ext = "jpg"
        case "image/png":
            body = data
            ext = "png"
        default:
            guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.95) else { return nil }
            body = jpeg
            ext = "jpg"
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProfilePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(fileName(title)).appendingPathExtension(ext)
        do {
            try body.write(to: file, options: .atomic)
            return file
        } catch {
            Log.warning(.media, "Фото профиля не записалось: \(error)")
            return nil
        }
    }

    /// «Фото — Анна Петрова» без знаков, которые файловая система не любит.
    nonisolated static func fileName(_ title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let clean = String(String.UnicodeScalarView(title.unicodeScalars.filter { !banned.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        let short = String(clean.prefix(60))
        return short.isEmpty ? "Фото профиля" : "Фото — \(short)"
    }
}

extension View {
    /// Окна «Поделиться» и «Сохранить в Файлы» для фото профиля. Вешать на сам просмотр:
    /// из-под открытого просмотра экран окно показать не может.
    func profilePhotoExport(_ saver: ProfilePhotoSaver) -> some View {
        sheet(item: Binding(get: { saver.export }, set: { if $0 == nil, let open = saver.export { saver.finishExport(saved: false, share: open.share) } })) { export in
            if export.share {
                ShareSheet(urls: [export.file]) { saver.finishExport(saved: false, share: true) }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            } else {
                FileExportPicker(urls: [export.file]) { saved in saver.finishExport(saved: saved, share: false) }
                    .ignoresSafeArea()
            }
        }
    }
}
