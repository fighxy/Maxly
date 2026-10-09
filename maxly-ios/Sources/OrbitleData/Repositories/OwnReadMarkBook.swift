import Foundation
import OrbitleDomain

/// Свои отметки прочтения по чатам: ответ сервера на свою отметку, пуш прочтения с другого
/// устройства и местная отметка ядра, пока отметки о прочтении скрыты. Свою позицию чата
/// (`OwnReadMark.position`) экран чата спрашивает синхронно при открытии, поэтому книга
/// читается без актора репозитория, под замком.
final class OwnReadMarkBook: @unchecked Sendable {
    private let lock = NSLock()
    private var replied: [String: Int64] = [:]
    private var pushed: [String: Int64] = [:]
    private var local: (@Sendable (String) -> Int64)?

    /// Последняя применённая своя отметка с сервера (ответ или пуш): запоздавший ответ на более
    /// старую отметку не применяется.
    func known(_ chatId: String) -> Int64 {
        lock.withLock { max(replied[chatId] ?? 0, pushed[chatId] ?? 0) }
    }

    /// Ответ сервера на свою отметку.
    func noteReply(_ mark: Int64, chatId: String) {
        lock.withLock { replied[chatId] = max(replied[chatId] ?? 0, mark) }
    }

    /// Своя отметка из пуша прочтения.
    func notePush(_ mark: Int64, chatId: String) {
        lock.withLock { pushed[chatId] = max(pushed[chatId] ?? 0, mark) }
    }

    /// Отметка сервера ушла назад (чат помечен непрочитанным).
    func forget(_ chatId: String) {
        lock.withLock {
            replied[chatId] = nil
            pushed[chatId] = nil
        }
    }

    func removeAll() {
        lock.withLock {
            replied.removeAll()
            pushed.removeAll()
        }
    }

    /// Откуда брать местную отметку (`GhostControls.localReadMark`). `nil` — её нет.
    func setLocal(_ source: (@Sendable (String) -> Int64)?) {
        lock.withLock { local = source }
    }

    /// Своя позиция чата: самая свежая из трёх отметок. Ядро спрашивается вне замка.
    func position(_ chatId: String) -> Int64 {
        let (card, push, source) = lock.withLock { (replied[chatId] ?? 0, pushed[chatId] ?? 0, local) }
        return OwnReadMark.position(card: card, pushed: push, local: source?(chatId) ?? 0)
    }
}
