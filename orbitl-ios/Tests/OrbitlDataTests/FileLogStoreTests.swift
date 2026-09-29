import Foundation
import Testing
import OrbitlDomain
@testable import OrbitlData

@Suite("Журнал в файлах")
struct FileLogStoreTests {
    private func makeStore(maxFileSize: Int = 1_000_000, maxFiles: Int = 3) -> FileLogStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("logs-\(UUID().uuidString)", isDirectory: true)
        return FileLogStore(directory: directory, maxFileSize: maxFileSize, maxFiles: maxFiles)
    }

    private func entry(_ message: String, level: Log.Level = .info) -> Log.Entry {
        Log.Entry(date: Date(timeIntervalSince1970: 0), level: level, category: .auth, message: message)
    }

    @Test("Запись попадает в файл с уровнем и разделом")
    func writes() throws {
        let store = makeStore()
        store.write(entry("код отправлен"))
        store.flush()
        let files = store.files()
        #expect(files.count == 1)
        let text = try String(contentsOf: files[0], encoding: .utf8)
        #expect(text.contains("INFO [auth] код отправлен"))
        #expect(store.totalSize() > 0)
    }

    @Test("Большой журнал разбивается на файлы, самый старый удаляется")
    func rotates() {
        let store = makeStore(maxFileSize: 100, maxFiles: 3)
        for index in 0..<20 {
            store.write(entry("строка номер \(index) с запасом длины"))
        }
        store.flush()
        #expect(store.files().count == 3)
        #expect(store.totalSize() <= 3 * 100 + 100)
    }

    @Test("Выключенный журнал не пишет в файлы, очистка удаляет их")
    func disableAndClear() {
        let store = makeStore()
        store.write(entry("до"))
        store.flush()
        store.clear()
        #expect(store.files().isEmpty)
        store.isEnabled = false
        store.write(entry("после"))
        store.flush()
        #expect(store.files().isEmpty)
    }

    @Test("ZIP собирается из файлов журнала")
    func archive() throws {
        let store = makeStore()
        store.write(entry("для архива"))
        let archive = try store.makeArchive(info: "Orbitl test")
        defer { try? FileManager.default.removeItem(at: archive) }
        let data = try Data(contentsOf: archive)
        // Локальный заголовок ZIP: `PK\u{3}\u{4}`.
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(archive.pathExtension == "zip")
    }

    @Test("Номер телефона маскируется")
    func maskPhone() {
        #expect(Log.mask(phone: "+79991234567") == "+7999***4567")
        #expect(Log.mask(phone: "12345") == "*****")
    }
}
