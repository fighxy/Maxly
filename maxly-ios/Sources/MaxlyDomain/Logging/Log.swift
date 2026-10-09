import Foundation

/// Журнал приложения для отладки.
///
/// Любой слой пишет сюда через `Log.info(.auth, "…")`. Куда уходят записи, решает приложение:
/// при запуске оно ставит `Log.sink` (файл на устройстве и системный журнал). Без приёмника
/// записи просто теряются, поэтому тесты и превью ничего не настраивают.
///
/// Коды из SMS, пароли, токены и текст сообщений в журнал не пишутся. Номер телефона
/// маскируется через `Log.mask(phone:)`.
public enum Log {
    public enum Level: String, Sendable, Comparable, CaseIterable {
        case debug, info, warning, error

        public static func < (lhs: Level, rhs: Level) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    /// Раздел, откуда пришла запись. По нему удобно фильтровать выгруженный журнал.
    public enum Category: String, Sendable {
        case app, auth, core, sync, chats, messages, contacts, calls, media, ui, settings
    }

    public struct Entry: Sendable {
        public let date: Date
        public let level: Level
        public let category: Category
        public let message: String

        public init(date: Date, level: Level, category: Category, message: String) {
            self.date = date
            self.level = level
            self.category = category
            self.message = message
        }
    }

    /// Приёмник записей. Меняется только при запуске приложения.
    nonisolated(unsafe) public static var sink: (@Sendable (Entry) -> Void)?

    public static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.debug, category, message)
    }

    public static func info(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.info, category, message)
    }

    public static func warning(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.warning, category, message)
    }

    public static func error(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.error, category, message)
    }

    public static func write(_ level: Level, _ category: Category, _ message: @autoclosure () -> String) {
        emit(level, category, message)
    }

    /// `+79991234567` → `+7999***4567`: видно страну и хвост, но не весь номер.
    public static func mask(phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        guard digits.count > 6 else { return String(repeating: "*", count: digits.count) }
        let prefix = phone.hasPrefix("+") ? "+" : ""
        return prefix + digits.prefix(4) + "***" + digits.suffix(4)
    }

    private static func emit(_ level: Level, _ category: Category, _ message: () -> String) {
        guard let sink else { return }
        sink(Entry(date: Date(), level: level, category: category, message: message()))
    }
}
