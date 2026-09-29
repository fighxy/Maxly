import Foundation
import OrbitleDomain
import os

/// Журнал в файлах на устройстве: запись, ротация, размер, очистка и ZIP для выгрузки.
///
/// Записи идут в `orbitle-0.log`; когда файл дорастает до `maxFileSize`, он становится
/// `orbitle-1.log`, прежние сдвигаются, а самый старый (`maxFiles - 1`) удаляется. Все
/// операции с файлами идут через одну последовательную очередь, так что писать можно
/// с любого потока. Каждая запись дублируется в системный журнал (`os.Logger`).
///
/// Запись в файлы можно выключить (`isEnabled`), системный журнал пишется всегда.
public final class FileLogStore: @unchecked Sendable {
    public static let fileExtension = "log"

    public let directory: URL
    private let maxFileSize: Int
    private let maxFiles: Int
    private let queue = DispatchQueue(label: "app.orbitle.log")
    private let formatter: ISO8601DateFormatter
    private var handle: FileHandle?
    private var currentSize = 0
    private var enabled: Bool
    private var loggers: [Log.Category: Logger] = [:]

    public init(directory: URL, maxFileSize: Int = 1_000_000, maxFiles: Int = 5, enabled: Bool = true) {
        self.directory = directory
        self.maxFileSize = maxFileSize
        self.maxFiles = max(maxFiles, 1)
        self.enabled = enabled
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    /// Каталог журнала в Application Support приложения.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Logs", isDirectory: true)
    }

    /// Приёмник для `Log.sink`.
    public var sink: @Sendable (Log.Entry) -> Void {
        { [weak self] entry in self?.write(entry) }
    }

    public var isEnabled: Bool {
        get { queue.sync { enabled } }
        set {
            queue.sync {
                enabled = newValue
                if !newValue { closeHandle() }
            }
        }
    }

    public func write(_ entry: Log.Entry) {
        queue.async { [self] in
            logger(for: entry.category).log(level: entry.level.osLevel, "\(entry.message, privacy: .public)")
            guard enabled else { return }
            let line = "\(formatter.string(from: entry.date)) \(entry.level.rawValue.uppercased()) [\(entry.category.rawValue)] \(entry.message)\n"
            append(Data(line.utf8))
        }
    }

    /// Дождаться записи всего, что уже поставлено в очередь.
    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    /// Файлы журнала, от свежего к старому.
    public func files() -> [URL] {
        queue.sync { existingFiles() }
    }

    /// Сколько байт занимает журнал.
    public func totalSize() -> Int {
        queue.sync {
            existingFiles().reduce(0) { sum, url in
                sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }

    public func clear() {
        queue.sync {
            closeHandle()
            existingFiles().forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// ZIP со всеми файлами журнала, отчётами о сбоях и `info.txt` (версия, устройство, время выгрузки) во временном
    /// каталоге. Архив собирает система (`NSFileCoordinator` с `.forUploading`), без сторонних библиотек.
    public func makeArchive(info: String, now: Date = Date()) throws -> URL {
        let stamp = Self.fileStamp(now)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("orbitle-logs-\(stamp)", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        queue.sync {
            try? handle?.synchronize()
            for file in existingFiles() + reportFiles() {
                try? FileManager.default.copyItem(at: file, to: staging.appendingPathComponent(file.lastPathComponent))
            }
            // Архив отчётов о сбоях (`CrashDumpStore`) — отдельной папкой.
            let crashes = directory.appendingPathComponent(CrashDumpStore.directoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: crashes.path) {
                try? FileManager.default.copyItem(at: crashes, to: staging.appendingPathComponent(CrashDumpStore.directoryName, isDirectory: true))
            }
        }
        try Data(info.utf8).write(to: staging.appendingPathComponent("info.txt"))

        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("orbitle-logs-\(stamp).zip")
        try? FileManager.default.removeItem(at: archive)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: archive)
            } catch {
                copyError = error
            }
        }
        try? FileManager.default.removeItem(at: staging)
        if let error = coordinationError ?? copyError { throw error }
        return archive
    }

    static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    // MARK: Внутреннее (только на `queue`)

    private func fileURL(_ index: Int) -> URL {
        directory.appendingPathComponent("orbitle-\(index).\(Self.fileExtension)")
    }

    /// Отчёты о сбоях (`*.txt`), которые аварийный журнал кладёт в тот же каталог.
    private func reportFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".txt") }.sorted().map { directory.appendingPathComponent($0) }
    }

    private func existingFiles() -> [URL] {
        (0..<maxFiles).map(fileURL).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func append(_ data: Data) {
        if handle == nil { openHandle() }
        if currentSize + data.count > maxFileSize, currentSize > 0 {
            rotate()
            openHandle()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            currentSize += data.count
        } catch {
            closeHandle()
        }
    }

    private func openHandle() {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(0)
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        currentSize = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
        currentSize = 0
    }

    private func rotate() {
        closeHandle()
        let manager = FileManager.default
        try? manager.removeItem(at: fileURL(maxFiles - 1))
        for index in stride(from: maxFiles - 2, through: 0, by: -1) {
            let from = fileURL(index)
            guard manager.fileExists(atPath: from.path) else { continue }
            try? manager.moveItem(at: from, to: fileURL(index + 1))
        }
    }

    private func logger(for category: Log.Category) -> Logger {
        if let logger = loggers[category] { return logger }
        let logger = Logger(subsystem: "app.orbitle.ios", category: category.rawValue)
        loggers[category] = logger
        return logger
    }
}

private extension Log.Level {
    var osLevel: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
