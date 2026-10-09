import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyData

@Suite("Кэш на устройстве")
struct DeviceStorageTests {
    /// Папка на тест и свой набор настроек, чтобы тесты не трогали `UserDefaults.standard`.
    private final class Sandbox: @unchecked Sendable {
        let root: URL
        let layout: StorageLayout
        let suite: String

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "orbitle-storage-\(UUID().uuidString)", directoryHint: .isDirectory)
            layout = StorageLayout(root: root.appending(path: "media", directoryHint: .isDirectory))
            try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
            suite = "orbitle.tests.\(UUID().uuidString)"
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }

        @discardableResult
        func file(_ category: StorageCategory, _ name: String, bytes: Int, age: TimeInterval = 0, now: Date = Date()) throws -> URL {
            let url = try layout.prepared(category).appending(path: name)
            try Data(count: bytes).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    }

    @Test("Размеры считаются по категориям, база отдельно")
    func usageByCategory() async throws {
        let box = try Sandbox()
        try box.file(.photos, "a", bytes: 10_000)
        try box.file(.photos, "b", bytes: 10_000)
        try box.file(.voice, "v.ogg", bytes: 5_000)
        let database = box.root.appending(path: "db", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try Data(count: 7_000).write(to: database.appending(path: "Maxly.store"))
        let storage = DeviceStorage(layout: box.layout, database: database, defaultsSuite: box.suite)

        let usage = await storage.usage()
        #expect(usage.bytes(.photos) >= 20_000)
        #expect(usage.bytes(.voice) >= 5_000)
        #expect(usage.bytes(.videos) == 0)
        #expect(usage.database >= 7_000)
        #expect(usage.cache == usage.categories.values.reduce(0, +))
        #expect(usage.total == usage.cache + usage.database)
    }

    @Test("Очистка категории не трогает остальные и базу")
    func clearCategory() async throws {
        let box = try Sandbox()
        let photo = try box.file(.photos, "a", bytes: 100)
        let file = try box.file(.files, "doc.pdf", bytes: 100)
        let storage = DeviceStorage(layout: box.layout, defaultsSuite: box.suite)

        await storage.clear([.photos])
        #expect(!box.exists(photo))
        #expect(box.exists(file))
        #expect(await storage.usage().bytes(.photos) == 0)
    }

    @Test("«Прочее»: свежие файлы отправки остаются, старые и файлы прежней раскладки удаляются")
    func clearOther() async throws {
        let box = try Sandbox()
        let outgoing = box.root.appending(path: "Outgoing", directoryHint: .isDirectory)
        let fresh = outgoing.appending(path: "1/voice.ogg")
        let stale = outgoing.appending(path: "2/note.mp4")
        for url in [fresh, stale] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: 50).write(to: url)
        }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 86_400)], ofItemAtPath: stale.path)
        let legacy = box.layout.root.appending(path: "123.ogg")
        try Data(count: 50).write(to: legacy)
        let storage = DeviceStorage(
            layout: box.layout,
            extras: [DeviceStorage.Extra(url: outgoing, minimumAge: 86_400)],
            defaultsSuite: box.suite
        )

        #expect(await storage.usage().bytes(.other) >= 150)
        await storage.clear([.other])
        #expect(box.exists(fresh))
        #expect(!box.exists(stale))
        #expect(!box.exists(legacy))
        // Пустая папка вложения убрана.
        #expect(!box.exists(stale.deletingLastPathComponent()))
    }

    @Test("Срок хранения: давно не открытое удаляется")
    func keepMedia() async throws {
        let box = try Sandbox()
        let old = try box.file(.videos, "old.mp4", bytes: 100, age: 8 * 86_400)
        let recent = try box.file(.videos, "new.mp4", bytes: 100, age: 86_400)
        let storage = DeviceStorage(layout: box.layout, defaultsSuite: box.suite)

        await storage.setPolicy(StoragePolicy(keepMedia: .week, sizeLimit: .unlimited))
        #expect(!box.exists(old))
        #expect(box.exists(recent))
    }

    @Test("«Всегда»: срок не удаляет ничего")
    func keepForever() async throws {
        let box = try Sandbox()
        let old = try box.file(.videos, "old.mp4", bytes: 100, age: 400 * 86_400)
        let storage = DeviceStorage(layout: box.layout, defaultsSuite: box.suite)

        await storage.setPolicy(StoragePolicy(keepMedia: .forever, sizeLimit: .unlimited))
        #expect(box.exists(old))
    }

    @Test("Сверх предела вытесняется самое давно использованное")
    func sizeLimit() {
        let now = Date()
        func entry(_ name: String, _ size: Int64, age: TimeInterval) -> DeviceStorage.Entry {
            DeviceStorage.Entry(url: URL(fileURLWithPath: "/tmp/\(name)"), size: size, date: now.addingTimeInterval(-age))
        }
        let oldest = entry("oldest", 600, age: 300)
        let middle = entry("middle", 300, age: 200)
        let newest = entry("newest", 300, age: 100)
        let policy = StoragePolicy(keepMedia: .forever, sizeLimit: .unlimited)
        #expect(DeviceStorage.expired([newest, oldest, middle], policy: policy, now: now, limit: 1000) == [oldest])
        #expect(DeviceStorage.expired([newest, oldest, middle], policy: policy, now: now, limit: 250) == [oldest, middle, newest])
        #expect(DeviceStorage.expired([newest, oldest, middle], policy: policy, now: now).isEmpty)
        // Срок и предел вместе: сначала уходит просроченное.
        let week = StoragePolicy(keepMedia: .week, sizeLimit: .unlimited)
        let stale = entry("stale", 10, age: 8 * 86_400)
        #expect(DeviceStorage.expired([stale, newest], policy: week, now: now, limit: 1000) == [stale])
    }

    @Test("Правила сохраняются между запусками, по умолчанию месяц и 5 ГБ")
    func policyPersists() async throws {
        let box = try Sandbox()
        #expect(await DeviceStorage(layout: box.layout, defaultsSuite: box.suite).policy() == StoragePolicy(keepMedia: .month, sizeLimit: .gb5))
        await DeviceStorage(layout: box.layout, defaultsSuite: box.suite).setPolicy(StoragePolicy(keepMedia: .threeDays, sizeLimit: .gb20))
        #expect(await DeviceStorage(layout: box.layout, defaultsSuite: box.suite).policy() == StoragePolicy(keepMedia: .threeDays, sizeLimit: .gb20))
    }

    @Test("Медиа ложится в папку своей категории, файл прежней раскладки переезжает")
    func mediaFolders() async throws {
        let box = try Sandbox()
        let legacy = box.layout.root.appending(path: "v1.ogg")
        try Data("ogg".utf8).write(to: legacy)
        let media = MediaRepositoryImpl(http: URLSessionClient(configuration: .ephemeral), layout: box.layout)

        let voice = MediaItem(id: "v1", type: .audio, url: URL(string: "https://cdn.invalid/v1.ogg")!, size: 3)
        let found = try await media.preview(for: voice)
        #expect(found.deletingLastPathComponent().lastPathComponent == StorageCategory.voice.folder)
        #expect(!box.exists(legacy))
        #expect(box.exists(found))
    }

    @Test("Кружок — своя категория кэша")
    func videoNoteCategory() {
        let round = VideoContent(id: "n", url: URL(string: "https://cdn.invalid/n.mp4"), isRound: true)
        let video = VideoContent(id: "v", url: URL(string: "https://cdn.invalid/v.mp4"))
        #expect(round.cacheItem()?.type.storageCategory == .videoNotes)
        #expect(video.cacheItem()?.type.storageCategory == .videos)
    }
}
