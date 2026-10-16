import Foundation

/// Очередь pingback gifka.me: события копятся и уходят пачкой через `delay` (или сразу,
/// набрав `maxBatch`). Показ одного медиа считается один раз за жизнь очереди (панель открыта).
/// Ничего не ждёт и не бросает: ошибка сети — события просто теряются.
public actor GifkaPingback {
    public typealias Sender = @Sendable ([GifkaEvent]) async -> Void

    private let sender: Sender
    private let delay: Duration
    private let maxBatch: Int
    private var queue: [GifkaEvent] = []
    private var viewed: Set<String> = []
    private var timer: Task<Void, Never>?

    public init(delay: Duration = .seconds(2), maxBatch: Int = 50, sender: @escaping Sender) {
        self.delay = delay
        self.maxBatch = max(1, maxBatch)
        self.sender = sender
    }

    /// Очередь поверх клиента; без ключа `nil`: pingback без ключа API не принимает.
    public init?(client: GifkaClient) {
        guard client.hasKey else { return nil }
        self.init { await client.pingback($0) }
    }

    public func views(_ ids: [String]) {
        for id in ids where !id.isEmpty && viewed.insert(id).inserted {
            queue.append(GifkaEvent(mediaId: id, kind: .view))
        }
        schedule()
    }

    public func click(_ id: String) { add(GifkaEvent(mediaId: id, kind: .click)) }
    public func send(_ id: String) { add(GifkaEvent(mediaId: id, kind: .send)) }

    /// Отправить накопленное сейчас (панель закрылась).
    public func flush() {
        timer?.cancel()
        timer = nil
        let batch = queue
        queue.removeAll()
        let sender = sender
        var start = 0
        while start < batch.count {
            let chunk = Array(batch[start..<min(start + maxBatch, batch.count)])
            start += maxBatch
            Task { await sender(chunk) }
        }
    }

    private func add(_ event: GifkaEvent) {
        guard !event.mediaId.isEmpty else { return }
        queue.append(event)
        schedule()
    }

    private func schedule() {
        guard !queue.isEmpty else { return }
        if queue.count >= maxBatch {
            flush()
            return
        }
        guard timer == nil else { return }
        let delay = delay
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.timerFired()
        }
    }

    private func timerFired() {
        timer = nil
        flush()
    }
}
