import Darwin
import Foundation
import OrbitlDomain

/// Аварийный журнал: сбой, после которого приложение закрывается, оставляет отчёт в файле.
///
/// Ловит три вида сбоев:
/// - исключения Objective-C (`NSSetUncaughtExceptionHandler`);
/// - сигналы аварийного завершения (`SIGABRT`, `SIGTRAP`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`):
///   так заканчиваются и ошибки самого Swift (например, проверки изоляции Swift 6);
/// - необработанные исключения ядра Kotlin (ядро передаёт текст через `record(_:)`).
///
/// Обработчик сигнала пишет только вызовами, безопасными в обработчике (`write`,
/// `backtrace_symbols_fd`), в файл, открытый заранее. При следующем запуске
/// `pendingReport()` отдаёт отчёт, а экран предлагает выгрузить журнал.
enum CrashReporter {
    /// Каталог с журналом приложения. Отчёт лежит рядом, чтобы попасть в ZIP.
    nonisolated(unsafe) private static var directory: URL?
    nonisolated(unsafe) private static var signalFD: Int32 = -1
    nonisolated(unsafe) private static var installed = false

    static let reportName = "last-crash.txt"

    /// Включить перехват. Вызывается один раз при запуске, до всего остального.
    static func install(directory: URL) {
        guard !installed else { return }
        installed = true
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Файл для обработчика сигнала открывается сейчас: в самом обработчике открывать нельзя.
        let signalPath = directory.appendingPathComponent("signal-crash.txt").path
        signalFD = open(signalPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            CrashReporter.record("Исключение Objective-C: \(exception.name.rawValue): \(exception.reason ?? "")\n\(stack)")
        }
        for sig in [SIGABRT, SIGTRAP, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig, crashSignalHandler)
        }
    }

    /// Записать отчёт о сбое сразу, без очереди журнала: процесс вот-вот завершится.
    static func record(_ text: String) {
        guard let directory else { return }
        let header = "Сбой \(ISO8601DateFormatter().string(from: Date())), \(AppInfo.version)\n"
        let url = directory.appendingPathComponent(reportName)
        try? Data((header + text + "\n").utf8).write(to: url, options: .atomic)
    }

    /// Отчёт прошлого запуска, если он завершился сбоем. `nil`, если всё было штатно.
    static func pendingReport() -> String? {
        guard let directory else { return nil }
        var parts: [String] = []
        if let text = try? String(contentsOf: directory.appendingPathComponent(reportName), encoding: .utf8), !text.isEmpty {
            parts.append(text)
        }
        if let text = previousSignalReport, !text.isEmpty {
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Отчёт обработчика сигнала, прочитанный до того, как `install` обнулил файл.
    nonisolated(unsafe) private static var previousSignalReport: String?

    /// Прочитать отчёт обработчика сигнала от прошлого запуска. Вызывается до `install`.
    static func loadPreviousSignalReport(directory: URL) {
        let path = directory.appendingPathComponent("signal-crash.txt")
        previousSignalReport = try? String(contentsOf: path, encoding: .utf8)
        // Сохраняем копию рядом с журналом, чтобы она попала в ZIP после следующего обнуления.
        if let text = previousSignalReport, !text.isEmpty {
            try? Data(text.utf8).write(to: directory.appendingPathComponent("previous-signal-crash.txt"), options: .atomic)
        }
    }

    /// Отчёт показан и выгружен (или пропущен): следующий запуск его не показывает.
    static func clearPendingReport() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(reportName))
        previousSignalReport = nil
    }

    fileprivate static func writeSignal(_ sig: Int32) {
        let fd = signalFD
        guard fd >= 0 else { return }
        var header = "Сбой по сигналу \(sig)\n".utf8CString
        header.withUnsafeBufferPointer { buffer in
            _ = write(fd, buffer.baseAddress, buffer.count - 1)
        }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
        let count = backtrace(&frames, Int32(frames.count))
        backtrace_symbols_fd(&frames, count, fd)
        fsync(fd)
    }
}

/// Обработчик сигнала: записать стек и вернуть сигналу стандартное поведение,
/// чтобы система всё равно завершила процесс и сохранила свой отчёт.
private func crashSignalHandler(_ sig: Int32) {
    CrashReporter.writeSignal(sig)
    signal(sig, SIG_DFL)
    raise(sig)
}

/// Версия приложения для отчётов и журнала.
enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Orbitl \(version) (\(build)), \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
