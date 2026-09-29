import Foundation

/// Состояние соединения с сервером для индикатора на экране.
public enum ConnectionState: Sendable, Equatable {
    /// Соединение установлено.
    case online
    /// Идёт подключение или переподключение.
    case connecting
    /// Соединения нет. Экран работает с локальной базой.
    case offline
}

/// Источник состояния соединения. Первое значение потока приходит сразу.
public protocol ConnectionStatusProvider: Sendable {
    func connectionStates() -> AsyncStream<ConnectionState>
}
