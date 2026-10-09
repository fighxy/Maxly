import Foundation

/// Один закреп чата. Список в плашке идёт от нового к старому.
public struct ChatPin: Equatable, Sendable {
    public var messageId: String
    public var text: String

    public init(messageId: String, text: String) {
        self.messageId = messageId
        self.text = text
    }
}

/// Плашка закрепов. Касание открывает текущий и переходит к более старому.
public struct PinBar: Equatable, Sendable {
    public private(set) var pins: [ChatPin]
    public private(set) var index: Int

    public init(pins: [ChatPin] = [], index: Int = 0) {
        self.pins = pins
        self.index = pins.isEmpty ? 0 : min(max(index, 0), pins.count - 1)
    }

    public var current: ChatPin? {
        guard pins.indices.contains(index) else { return nil }
        return pins[index]
    }

    /// «2 из 5», когда закрепов несколько. Один закреп без счётчика.
    public var counter: String? {
        guard pins.count > 1 else { return nil }
        return "\(index + 1) из \(pins.count)"
    }

    /// Сообщение, к которому перейти. После этого показан следующий более старый закреп.
    public mutating func advance() -> String? {
        guard let current else { return nil }
        if pins.count > 1 {
            index = (index + 1) % pins.count
        }
        return current.messageId
    }

    /// Событие `pinned`. Текст нового закрепа, если он уже известен.
    public mutating func apply(action: String, messageId: String, text: String = "") {
        switch action {
        case "pin":
            guard !messageId.isEmpty else { return }
            pins.removeAll { $0.messageId == messageId }
            let title = text.isEmpty ? "Сообщение" : text
            pins.insert(ChatPin(messageId: messageId, text: title), at: 0)
            index = 0
        case "unpin":
            pins.removeAll { $0.messageId == messageId }
            if pins.isEmpty { index = 0 }
            else if index >= pins.count { index = pins.count - 1 }
        case "unpinAll":
            pins = []
            index = 0
        default:
            break
        }
    }

    /// Ответ 241 заменяет список. Пустой ответ не стирает уже показанное,
    /// если сервер просто не прислал страницу: пустой массив всё же значит «закрепов нет».
    public mutating func replace(_ pins: [ChatPin]) {
        self.pins = pins
        index = pins.isEmpty ? 0 : min(index, pins.count - 1)
    }
}

/// Пуш `pinned`. База его не пишет: открытый чат обновляет плашку.
public struct PinPush: Equatable, Sendable {
    public var chatId: String
    public var action: String
    public var messageId: String
    /// Сколько закрепов осталось. `-1` — пуш число не принёс.
    public var count: Int

    public init(chatId: String, action: String, messageId: String, count: Int) {
        self.chatId = chatId
        self.action = action
        self.messageId = messageId
        self.count = count
    }
}

/// Раздаёт пуши закрепов всем открытым чатам. Поток ядра один, слушателей много.
public final class PinHub: @unchecked Sendable {
    private let lock = NSLock()
    private var listeners: [UUID: AsyncStream<PinPush>.Continuation] = [:]

    public init() {}

    public func pins() -> AsyncStream<PinPush> {
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

    public func publish(_ push: PinPush) {
        lock.lock()
        let current = Array(listeners.values)
        lock.unlock()
        for continuation in current {
            continuation.yield(push)
        }
    }
}
