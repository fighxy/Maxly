import Foundation
import Network
import Observation
import MaxlyPresentation

/// Текущая сеть для «Автовоспроизведения GIF»: Wi‑Fi, сотовая или нет сети.
@MainActor
@Observable
final class NetworkKindMonitor {
    static let shared = NetworkKindMonitor()

    private(set) var kind: NetworkKind = .other
    /// Режим экономии трафика или сеть с лимитом.
    private(set) var constrained = false

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let kind = Self.kind(of: path)
            let constrained = path.isConstrained
            Task { @MainActor in
                NetworkKindMonitor.shared.kind = kind
                NetworkKindMonitor.shared.constrained = constrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "maxly.network-kind"))
    }

    nonisolated private static func kind(of path: NWPath) -> NetworkKind {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }
}
