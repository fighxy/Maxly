import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Свои обои на диске")
@MainActor
struct CustomWallpaperStoreTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wallpapers-\(UUID().uuidString)", isDirectory: true)
    }

    private func files(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    @Test("Фото пишется файлом, список переживает новое хранилище")
    func saveAndReload() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCustomWallpaperStore(directory: directory)
        #expect(store.load().isEmpty)
        let saved = try store.save(image: Data([1, 2, 3]), dim: 0.25, blur: 0.5, for: .global)
        #expect(saved.file.hasPrefix("global-"))
        #expect(saved.file.hasSuffix(".jpg"))
        #expect(try Data(contentsOf: store.url(for: saved)) == Data([1, 2, 3]))
        #expect(files(in: directory) == [saved.file, FileCustomWallpaperStore.indexFile])
        let again = FileCustomWallpaperStore(directory: directory)
        #expect(again.load().global == saved)
        #expect(again.load().global?.dim == 0.25)
    }

    @Test("Новое фото того же чата заменяет файл, прежний удаляется")
    func replace() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCustomWallpaperStore(directory: directory)
        let first = try store.save(image: Data([1]), dim: 0.1, blur: 0, for: .chat("42"))
        let second = try store.save(image: Data([2]), dim: 0.1, blur: 0, for: .chat("42"))
        #expect(first.file != second.file)
        #expect(second.file.hasPrefix("chat-42-"))
        #expect(files(in: directory) == [second.file, FileCustomWallpaperStore.indexFile])
        #expect(store.load().chats == ["42": second])
    }

    @Test("Сброс обоев чата удаляет его файл и не трогает общие")
    func resetChat() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCustomWallpaperStore(directory: directory)
        let global = try store.save(image: Data([1]), dim: 0.1, blur: 0, for: .global)
        let own = try store.save(image: Data([2]), dim: 0.1, blur: 0, for: .chat("-7"))
        #expect(store.load().resolve(chatId: "-7") == own)
        store.remove(.chat("-7"))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: own).path))
        #expect(store.load().resolve(chatId: "-7") == global)
        #expect(FileCustomWallpaperStore(directory: directory).load() == CustomWallpaperIndex(global: global))
        store.remove(.global)
        #expect(files(in: directory) == [FileCustomWallpaperStore.indexFile])
        #expect(FileCustomWallpaperStore(directory: directory).load().isEmpty)
    }

    @Test("Испорченный список — своих обоев нет; лишние файлы и записи без файла убираются")
    func recovery() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent(FileCustomWallpaperStore.indexFile)
        try Data("{".utf8).write(to: indexURL)
        try Data([9]).write(to: directory.appendingPathComponent("chat-1-dead.jpg"))
        let broken = FileCustomWallpaperStore(directory: directory)
        #expect(broken.load().isEmpty)
        #expect(!files(in: directory).contains("chat-1-dead.jpg"))

        let kept = try broken.save(image: Data([1]), dim: 0.1, blur: 0, for: .chat("1"))
        let missing = CustomWallpaperIndex(chats: ["1": kept, "2": CustomWallpaper(file: "chat-2-gone.jpg")])
        try JSONEncoder().encode(missing).write(to: indexURL)
        #expect(FileCustomWallpaperStore(directory: directory).load().chats == ["1": kept])
    }

    @Test("Id чата в имени файла без опасных символов")
    func fileNames() {
        #expect(FileCustomWallpaperStore.fileName(for: .global, token: "abc") == "global-abc.jpg")
        #expect(FileCustomWallpaperStore.fileName(for: .chat("-100500"), token: "abc") == "chat--100500-abc.jpg")
        #expect(FileCustomWallpaperStore.fileName(for: .chat("../x/y"), token: "abc") == "chat-___x_y-abc.jpg")
        #expect(FileCustomWallpaperStore.safe("") == "_")
        #expect(FileCustomWallpaperStore.randomToken().count == 8)
    }
}
