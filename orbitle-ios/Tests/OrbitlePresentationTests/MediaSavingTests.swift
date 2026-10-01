import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Кэш медиа: кладёт файл с заданными первыми байтами, как скачанный с CDN без расширения.
private actor FakeMediaFiles: MediaRepository {
    private let directory: URL
    private let bytes: Data
    private(set) var fetched: [String] = []

    init(directory: URL, bytes: Data) {
        self.directory = directory
        self.bytes = bytes
    }

    func preview(for item: MediaItem) async throws(OrbitleError) -> URL {
        fetched.append(item.id)
        let file = directory.appending(path: item.id.filter { $0.isLetter || $0.isNumber })
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bytes.write(to: file)
        } catch {
            throw .storageError
        }
        return file
    }

    nonisolated func download(_ item: MediaItem) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func clearCache() async {}
}

private actor FakeGallery: GallerySaving {
    private(set) var saved: [[SavedFile]] = []
    var failure: OrbitleError?

    func fail(with error: OrbitleError) { failure = error }

    func save(_ files: [SavedFile]) async throws(OrbitleError) {
        if let failure { throw failure }
        saved.append(files)
    }
}

@Suite("Сохранение на телефон")
@MainActor
struct MediaSavingTests {
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1])
    private static let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func message(_ attachments: [ChatAttachment]) -> Message {
        Message(id: "42", chatId: "c", authorId: "bob", text: "", timestamp: Self.date, status: .sent, content: MessageContent(attachments: attachments))
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "orbitle-save-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("Имя по времени сообщения, номер со второго вложения")
    func naming() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(SaveNaming.name(for: Self.date, index: 0, ext: "jpg", timeZone: utc) == "Orbitle 2026-09-21 14.13.20.jpg")
        #expect(SaveNaming.name(for: Self.date, index: 2, ext: "mp4", timeZone: utc) == "Orbitle 2026-09-21 14.13.20 3.mp4")
    }

    @Test("Расширение картинки по первым байтам")
    func signatures() {
        #expect(SaveNaming.imageExtension(of: Self.jpeg) == "jpg")
        #expect(SaveNaming.imageExtension(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) == "png")
        #expect(SaveNaming.imageExtension(of: Data("RIFF\0\0\0\0WEBPVP8 ".utf8)) == "webp")
        #expect(SaveNaming.imageExtension(of: Data("\0\0\0\u{18}ftypheic".utf8)) == "heic")
        #expect(SaveNaming.imageExtension(of: Data("GIF89a".utf8)) == "gif")
    }

    @Test("В «Фото» — фото и видео, в «Файлы» — ещё голосовые и документы, контакт — никуда")
    func whatIsSaveable() {
        let photo = ChatAttachment.photo(PhotoContent(id: "p", url: URL(string: "https://cdn.invalid/p")))
        let voice = ChatAttachment.voice(VoiceContent(id: "v", url: URL(string: "https://cdn.invalid/v.ogg")))
        let file = ChatAttachment.file(FileContent(id: "f", name: "doc.pdf", url: URL(string: "https://cdn.invalid/f")))
        let contact = ChatAttachment.contact(ContactContent(id: "k", userId: "1", name: "Иван"))
        let all = message([photo, voice, file, contact])
        #expect(ChatViewModel.saveable(all, to: .photos).map(\.id) == ["p"])
        #expect(ChatViewModel.saveable(all, to: .files).map(\.id) == ["p", "v", "f"])
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), gallery: FakeGallery())
        #expect(model.canSave(message([voice]), to: .photos) == false)
        #expect(model.canSave(message([voice]), to: .files))
        #expect(model.canSave(message([contact]), to: .files) == false)
    }

    @Test("Фото с CDN без расширения уходит в «Фото» как JPEG с понятным именем")
    func photoToGallery() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let media = FakeMediaFiles(directory: folder, bytes: Self.jpeg)
        let gallery = FakeGallery()
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), media: media, gallery: gallery)
        let photo = PhotoContent(id: "p1", url: URL(string: "https://i.invalid/i?r=abc"))

        model.save(message([.photo(photo)]), to: .photos)
        #expect(await eventually { await gallery.saved.count == 1 })
        let file = try #require(await gallery.saved.first?.first)
        #expect(file.kind == .image)
        #expect(file.name.hasPrefix("Orbitle "))
        #expect(file.name.hasSuffix(".jpg"))
        #expect(file.url.lastPathComponent == file.name)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        #expect(await eventually { model.notice == "Фото сохранено в «Фото»" })
        #expect(model.isSaving == false)
    }

    @Test("Нет доступа к «Фото»: причина видна в уведомлении")
    func galleryDenied() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gallery = FakeGallery()
        await gallery.fail(with: .rejected("Нет доступа к «Фото»"))
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), media: FakeMediaFiles(directory: folder, bytes: Self.jpeg), gallery: gallery)
        model.save(message([.photo(PhotoContent(id: "p", url: URL(string: "https://i.invalid/p")))]), to: .photos)
        #expect(await eventually { model.notice == "Нет доступа к «Фото»" })
    }

    @Test("В «Файлы»: окно с файлами под их именами, после сохранения — уведомление")
    func filesExport() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), media: FakeMediaFiles(directory: folder, bytes: Self.jpeg))
        let attachments: [ChatAttachment] = [
            .photo(PhotoContent(id: "p", url: URL(string: "https://i.invalid/p"))),
            .file(FileContent(id: "f", name: "Отчёт.pdf", size: 12, url: URL(string: "https://cdn.invalid/f"))),
        ]

        model.save(message(attachments), to: .files)
        #expect(await eventually { model.fileExport != nil })
        let export = try #require(model.fileExport)
        #expect(export.fromViewer == false)
        #expect(export.files.map(\.url.lastPathComponent) == [export.files[0].name, "Отчёт.pdf"])
        model.finishFileExport(saved: true)
        #expect(model.fileExport == nil)
        #expect(model.notice == "Сохранено в «Файлы»: 2")
    }

    @Test("Отмена окна «Файлы» — без уведомления")
    func filesCancelled() async {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = ChatViewModel(chatId: "c", currentUserId: "me", messages: FakeMessageRepository(), media: FakeMediaFiles(directory: folder, bytes: Self.jpeg))
        model.save(message([.voice(VoiceContent(id: "v", url: URL(string: "https://cdn.invalid/v.ogg")))]), to: .files)
        #expect(await eventually { model.fileExport != nil })
        model.finishFileExport(saved: false)
        #expect(model.fileExport == nil)
        #expect(model.notice == nil)
    }
}
