import Foundation

/// Что умеет источник звонков.
public struct CallCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// История звонков аккаунта.
    public static let history = CallCapabilities(rawValue: 1 << 0)
    /// Удаление записей на сервере. Без него запись скрывается только на устройстве.
    public static let delete = CallCapabilities(rawValue: 1 << 1)
    /// Ссылка на новый звонок.
    public static let createLink = CallCapabilities(rawValue: 1 << 2)
    /// Вход в звонок по ссылке.
    public static let join = CallCapabilities(rawValue: 1 << 3)
}

public protocol CallHistoryRepository: Sendable {
    var capabilities: CallCapabilities { get }
    /// История, новые звонки сверху, и все её изменения.
    func calls() -> AsyncStream<[CallRecord]>
    func delete(ids: [String]) async throws(OrbitlError)
    func createCallLink() async throws(OrbitlError) -> URL
    func join(link: String) async throws(OrbitlError)
}

public extension CallHistoryRepository {
    func delete(ids: [String]) async throws(OrbitlError) { throw .invalidRequest }
    func createCallLink() async throws(OrbitlError) -> URL { throw .invalidRequest }
    func join(link: String) async throws(OrbitlError) { throw .invalidRequest }
}
