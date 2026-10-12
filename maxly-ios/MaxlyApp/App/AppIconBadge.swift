import Observation
import UserNotifications
import MaxlyDomain

/// Lives with the signed-in session, not a SwiftUI screen. Observation continues
/// while background execution is available. One writer prevents stale async counts
/// from overwriting a newer count (including logout's zero).
@MainActor
final class AppIconBadge {
    private var readCount: (() -> Int)?
    private var generation = 0
    private var desired = 0
    private var applied: Int?
    private var writer: Task<Void, Never>?

    func start(readCount: @escaping () -> Int) {
        generation &+= 1
        self.readCount = readCount
        observe(generation: generation)
    }

    func stop() {
        generation &+= 1
        readCount = nil
        update(0)
    }

    /// Retry after permission changes or a return from suspension.
    func refresh() {
        applied = nil
        update(readCount?() ?? 0)
    }

    private func observe(generation: Int) {
        guard generation == self.generation, let readCount else { return }
        let count = withObservationTracking {
            readCount()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observe(generation: generation)
            }
        }
        update(count)
    }

    private func update(_ count: Int) {
        desired = max(0, count)
        guard writer == nil, applied != desired else { return }
        writer = Task { [weak self] in
            guard let self else { return }
            defer { self.writer = nil }
            while self.applied != self.desired {
                let count = self.desired
                do {
                    try await UNUserNotificationCenter.current().setBadgeCount(count)
                    self.applied = count
                } catch {
                    Log.warning(.app, "Не удалось обновить бейдж приложения: \(error)")
                    // A future count change or foreground refresh retries; no busy loop.
                    return
                }
            }
        }
    }
}
