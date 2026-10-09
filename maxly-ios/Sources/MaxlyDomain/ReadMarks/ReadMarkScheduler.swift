import Foundation

/// Сообщение, до которого читается чат: id на сервере и его серверное время (мс).
public struct ReadMark: Hashable, Sendable {
    public var messageId: String
    public var time: Int64

    public init(messageId: String, time: Int64) {
        self.messageId = messageId
        self.time = time
    }

    /// Новее `other`: позже по времени, а при равном времени — с бо́льшим id сервера (он растёт
    /// с каждым сообщением). Нечисловой id не новее; `nil` — отметки ещё не было.
    public func isNewer(than other: ReadMark?) -> Bool {
        guard let other else { return true }
        if time != other.time { return time > other.time }
        guard let mine = Int64(messageId) else { return false }
        guard let theirs = Int64(other.messageId) else { return true }
        return mine > theirs
    }
}

/// Когда уходит отметка прочтения (`ReadMarkRules`).
///
/// - Отметка уходит через `ReadMarkRules.delay` после последней смены кандидата: каждый новый
///   кандидат перезапускает ожидание, поэтому быстрая прокрутка шлёт одну отметку — о последнем.
/// - Уходит только самый новый кандидат: тот же или более старый, чем ждущий, ожидание не
///   трогает.
/// - Отметка не новее уже отправленной не уходит никогда.
/// - `cancel()` снимает ждущую отметку (экран ушёл, приложение свёрнуто): невидимое не читается.
///   Отметка, чьё ожидание уже прошло, уходит до конца.
///
/// `send` отправляет и отвечает, удалось ли. Неудачная отметка не считается отправленной:
/// её повторит следующий кандидат. `sleep` подменяют тесты.
@MainActor
public final class ReadMarkScheduler {
    public private(set) var sent: ReadMark?
    public private(set) var pending: ReadMark?

    private let delay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let send: @MainActor (ReadMark) async -> Bool
    private var task: Task<Void, Never>?

    public init(
        delay: Duration = ReadMarkRules.delay,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        send: @escaping @MainActor (ReadMark) async -> Bool
    ) {
        self.delay = delay
        self.sleep = sleep
        self.send = send
    }

    /// Новый кандидат: самое новое увиденное сообщение.
    public func propose(_ mark: ReadMark) {
        guard mark.isNewer(than: sent) else { return }
        if let pending, !mark.isNewer(than: pending) { return }
        task?.cancel()
        pending = mark
        let sleep = sleep
        let delay = delay
        task = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.pending == mark else { return }
            await self.fire(mark)
        }
    }

    /// Снять ждущую отметку.
    public func cancel() {
        task?.cancel()
        task = nil
        pending = nil
    }

    /// Новый заход в чат (или чат помечен непрочитанным): прежние отметки забыты.
    public func reset() {
        cancel()
        sent = nil
    }

    private func fire(_ mark: ReadMark) async {
        // Ожидание прошло: дальше отправку не отменяет ни новый кандидат, ни уход с экрана.
        task = nil
        pending = nil
        let previous = sent
        sent = mark
        let delivered = await send(mark)
        if !delivered, sent == mark { sent = previous }
    }
}

public extension ReadMark {
    /// Время сообщения в мс, как его хранит сервер.
    static func time(of message: Message) -> Int64 {
        Int64((message.timestamp.timeIntervalSince1970 * 1000).rounded())
    }

    /// Отметка до этого сообщения. Только у сообщения, которое есть на сервере: отправлено и
    /// с числовым id. Своё ещё не ушедшее и служебные локальные строки отметкой не бывают.
    init?(message: Message) {
        let id = message.serverId ?? message.id
        guard message.status == .sent, Int64(id) != nil else { return nil }
        self.init(messageId: id, time: Self.time(of: message))
    }
}
