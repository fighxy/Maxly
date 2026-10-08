import Foundation

/// Пуш `scheduled`: создали, изменили, удалили или отправили отложенное.
public struct ScheduledPush: Equatable, Sendable {
    public var chatId: String
    public var messageId: String
    public var action: String

    public init(chatId: String, messageId: String, action: String) {
        self.chatId = chatId
        self.messageId = messageId
        self.action = action
    }
}

/// Раздаёт пуши отложенных сообщений. В базу они не пишутся.
public final class ScheduledHub: @unchecked Sendable {
    private let lock = NSLock()
    private var listeners: [UUID: AsyncStream<ScheduledPush>.Continuation] = [:]

    public init() {}

    public func events() -> AsyncStream<ScheduledPush> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            listeners[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.listeners[id] = nil
                self?.lock.unlock()
            }
        }
    }

    public func publish(_ push: ScheduledPush) {
        lock.lock()
        let current = Array(listeners.values)
        lock.unlock()
        for continuation in current { continuation.yield(push) }
    }
}
