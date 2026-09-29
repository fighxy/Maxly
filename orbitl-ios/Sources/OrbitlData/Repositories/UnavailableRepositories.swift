import Foundation
import OrbitlDomain

/// Контакты, пока мост ядра (`MaxIos`) их не отдаёт: пустой список без возможностей.
/// Экран по `capabilities` показывает, что раздел ещё недоступен.
public struct UnavailableContactRepository: ContactRepository {
    public init() {}

    public var capabilities: ContactCapabilities { [] }

    public func contacts() -> AsyncStream<[Contact]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

/// История звонков, пока мост ядра её не отдаёт.
public struct UnavailableCallHistoryRepository: CallHistoryRepository {
    public init() {}

    public var capabilities: CallCapabilities { [] }

    public func calls() -> AsyncStream<[CallRecord]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}
