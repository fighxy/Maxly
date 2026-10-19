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

    @Test("Фото пишется файлом, список с затемнением и размытием переживает новое хранилище")
    func saveAndReload() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCustomWallpaperStore(directory: directory)
        #expect(store.load() == .empty)
        let file = try store.savePhoto(Data([1, 2, 3]), for: .global)
        store.setDim(35)
        store.setBlur(true)
        #expect(file.hasPrefix("global-"))
        #expect(file.hasSuffix(".jpg"))
        #expect(try Data(contentsOf: store.url(forFile: file)) == Data([1, 2, 3]))
        #expect(files(in: directory) == [file, FileCustomWallpaperStore.indexFile])
        let again = FileCustomWallpaperStore(directory: directory).load()
        #expect(again == CustomWallpaperIndex(global: file, dimPercent: 35, blur: true))
    }

    @Test("Новое фото чата заменяет копию, прежняя и её размытый вариант удаляются")
    func replace() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCustomWallpaperStore(directory: directory)
        let first = try store.savePhoto(Data([1]), for: .chat("7.42"))
        try Data([9]).write(to: store.url(forFile: CustomWallpaperStyle.blurredName(first)))
        let second = try store.savePhoto(Data([2]), for: .chat("7.42"))
        #expect(first != second)
        #expect(files(in: directory) == [second, FileCustomWallpaperStore.indexFile])
        #expect(store.load().chats == ["7.42": second])
    }

    @Test("«Как в общих» и «Без обоев» удаляют фото чата и не трогают общее")
    func chatChoices() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCustomWallpaperStore(directory: directory)
        let global = try store.savePhoto(Data([1]), for: .global)
        let own = try store.savePhoto(Data([2]), for: .chat("7.-5"))
        #expect(store.load().resolve(chatKey: "7.-5") == .photo(own))
        store.setChat("7.-5", plain: true)
        #expect(!FileManager.default.fileExists(atPath: store.url(forFile: own).path))
        #expect(store.load().resolve(chatKey: "7.-5") == .plain)
        #expect(FileCustomWallpaperStore(directory: directory).load().choice(chatKey: "7.-5") == .plain)
        store.setChat("7.-5", plain: false)
        #expect(store.load().resolve(chatKey: "7.-5") == .photo(global))
        #expect(store.load().chats.isEmpty)
        store.resetGlobal()
        #expect(files(in: directory) == [FileCustomWallpaperStore.indexFile])
        #expect(FileCustomWallpaperStore(directory: directory).load().resolve(chatKey: "7.-5") == .preset)
    }

    @Test("Испорченный список — своих обоев нет; лишние файлы и фото без файла убираются")
    func recovery() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent(FileCustomWallpaperStore.indexFile)
        try Data("{".utf8).write(to: indexURL)
        try Data([9]).write(to: directory.appendingPathComponent("chat-dead.jpg"))
        let broken = FileCustomWallpaperStore(directory: directory)
        #expect(broken.load() == .empty)
        #expect(!files(in: directory).contains("chat-dead.jpg"))

        let kept = try broken.savePhoto(Data([1]), for: .chat("7.1"))
        try Data([3]).write(to: directory.appendingPathComponent(CustomWallpaperStyle.blurredName(kept)))
        let missing = CustomWallpaperIndex(chats: ["7.1": kept, "7.2": "chat-gone.jpg", "7.3": "plain", "7.4": "../evil.jpg"])
        try JSONEncoder().encode(missing).write(to: indexURL)
        let reopened = FileCustomWallpaperStore(directory: directory)
        #expect(reopened.load().chats == ["7.1": kept, "7.3": "plain"])
        // Размытый вариант живой копии остаётся.
        #expect(files(in: directory).contains(CustomWallpaperStyle.blurredName(kept)))
    }

    @Test("Имена копий: чьё фото и случайный хвост")
    func fileNames() {
        #expect(FileCustomWallpaperStore.fileName(for: .global, token: "abc") == "global-abc.jpg")
        #expect(FileCustomWallpaperStore.fileName(for: .chat("7.-100"), token: "abc") == "chat-abc.jpg")
        #expect(FileCustomWallpaperStore.randomToken().count == 8)
    }
}
