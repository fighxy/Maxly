import Foundation

/// Сохранённый отчёт о сбое.
public struct CrashDump: Identifiable, Hashable, Sendable {
    /// Имя файла: `crash-<дата>-<хэш>.txt`.
    public let id: String
    /// Когда сбой нашёлся (при запуске после него).
    public let date: Date
    /// Первая содержательная строка отчёта.
    public let summary: String
}

/// Архив отчётов о сбоях: каждый сбой остаётся в `Logs/Crashes/`, пока его не удалят.
///
/// Аварийный журнал держит только отчёт последнего сбоя и забывает его после экрана сбоя.
/// Сюда отчёт копируется при запуске, поэтому его можно открыть и позже, в «О приложении».
/// Один и тот же текст (или его часть) дважды не сохраняется, хранятся последние `limit` отчётов.
public struct CrashDumpStore: Sendable {
    public static let directoryName = "Crashes"

    public let directory: URL
    public let limit: Int

    public init(directory: URL, limit: Int = 20) {
        self.directory = directory
        self.limit = max(limit, 1)
    }

    /// Архив рядом с журналом: `Logs/Crashes`.
    public init(logsDirectory: URL, limit: Int = 20) {
        self.init(directory: logsDirectory.appendingPathComponent(Self.directoryName, isDirectory: true), limit: limit)
    }

    /// Сохранить отчёт. Если такой текст уже сохранён, вернуть его.
    @discardableResult
    public func save(_ text: String, date: Date = Date()) -> CrashDump? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hash = Self.hash(trimmed)
        // Тот же отчёт или его часть: приложение закрыли на экране сбоя, и при следующем
        // запуске аварийный журнал отдал отчёт снова (уже без обнулённого отчёта сигнала).
        for url in files() {
            let name = url.lastPathComponent
            let saved = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            guard name.hasSuffix("-\(hash).txt") || saved.contains(trimmed),
                  let date = Self.date(fromName: name) else { continue }
            return CrashDump(id: name, date: date, summary: Self.summary(of: saved))
        }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "crash-\(Self.stamp(date))-\(hash).txt"
        do {
            try Data((trimmed + "\n").utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        prune()
        return CrashDump(id: name, date: Self.date(fromName: name) ?? date, summary: Self.summary(of: trimmed))
    }

    /// Отчёты от свежего к старому.
    public func list() -> [CrashDump] {
        files().compactMap { url in
            let name = url.lastPathComponent
            guard let date = Self.date(fromName: name) else { return nil }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return CrashDump(id: name, date: date, summary: Self.summary(of: text))
        }
    }

    /// Полный текст отчёта.
    public func text(of dump: CrashDump) -> String? {
        try? String(contentsOf: directory.appendingPathComponent(dump.id), encoding: .utf8)
    }

    public func remove(_ dump: CrashDump) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(dump.id))
    }

    public func removeAll() {
        files().forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Файлы отчётов от свежего к старому (имя начинается с даты, поэтому порядок по имени).
    func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix("crash-") && $0.hasSuffix(".txt") }
            .sorted(by: >)
            .map { directory.appendingPathComponent($0) }
    }

    private func prune() {
        files().dropFirst(limit).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: Имя файла и краткая строка

    static func stamp(_ date: Date) -> String {
        formatter().string(from: date)
    }

    /// Дата из имени `crash-2026-09-29_23-10-05-<хэш>.txt`.
    static func date(fromName name: String) -> Date? {
        let prefix = "crash-"
        let length = "yyyy-MM-dd_HH-mm-ss".count
        guard name.hasPrefix(prefix), name.count >= prefix.count + length else { return nil }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(start, offsetBy: length)
        return formatter().date(from: String(name[start..<end]))
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    /// FNV-1a (64 бита) текста: одинаковый отчёт даёт одинаковое имя на любом устройстве.
    static func hash(_ text: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Первая содержательная строка: заголовок аварийного журнала («Сбой <дата>, Orbitle …»)
    /// пропускается, у сигнала добавляется его имя.
    public static func summary(of text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let line = lines.first(where: { !isHeader($0) }) ?? lines.first ?? ""
        let named = withSignalName(line)
        return named.count > 160 ? String(named.prefix(159)) + "…" : named
    }

    /// Заголовок `record(_:)`: «Сбой 2026-09-29T…, Orbitle 0.1.0 (1), …».
    private static func isHeader(_ line: String) -> Bool {
        guard line.hasPrefix("Сбой ") else { return false }
        let rest = line.dropFirst("Сбой ".count)
        return rest.first?.isNumber == true
    }

    private static func withSignalName(_ line: String) -> String {
        let prefix = "Сбой по сигналу "
        guard line.hasPrefix(prefix), let number = Int32(line.dropFirst(prefix.count)) else { return line }
        let names: [Int32: String] = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 10: "SIGBUS", 11: "SIGSEGV"]
        guard let name = names[number] else { return line }
        return "\(line) (\(name))"
    }
}
