import Foundation
import Observation
import MaxlyData

/// Настройки поиска gifka.me в приложении.
enum GifkaSettings {
    /// «Поиск GIF (gifka.me)»: по умолчанию выключен.
    static let enabledKey = "gifkaSearchEnabled"

    /// Ключ API из сборки (Info.plist `GifkaAPIKey`, заполняется на CI). Пусто — без ключа.
    static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "GifkaAPIKey") as? String
    }

    static let siteURL = URL(string: "https://gifka.me")!
}

/// Выдача gifka.me для панели: тренды при пустом запросе, поиск с задержкой при вводе.
@MainActor
@Observable
final class GifSearchModel {
    let type: GifkaClient.MediaType
    private(set) var items: [GifkaMedia] = []
    private(set) var loading = false
    private(set) var failure: String?
    private(set) var exhausted = false
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }

    @ObservationIgnored let client: GifkaClient
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var started = false
    private static let pageSize = 30
    private static let debounce: Duration = .milliseconds(400)

    init(type: GifkaClient.MediaType, client: GifkaClient) {
        self.type = type
        self.client = client
    }

    func start() {
        guard !started else { return }
        started = true
        load(reset: true, delay: false)
    }

    func loadMore() {
        guard !loading, !exhausted, !items.isEmpty else { return }
        load(reset: false, delay: false)
    }

    func retry() { load(reset: true, delay: false) }

    private func schedule() {
        load(reset: true, delay: true)
    }

    private func load(reset: Bool, delay: Bool) {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = reset ? 0 : items.count
        let client = client
        let type = type
        task = Task { [weak self] in
            if delay { try? await Task.sleep(for: Self.debounce) }
            guard !Task.isCancelled, let self else { return }
            self.loading = true
            self.failure = nil
            do {
                let page = text.isEmpty
                    ? try await client.trending(type: type, limit: Self.pageSize, offset: offset)
                    : try await client.search(text, type: type, limit: Self.pageSize, offset: offset)
                guard !Task.isCancelled else { return }
                let known = Set(reset ? [] : self.items.map(\.id))
                let fresh = page.items.filter { !known.contains($0.id) }
                self.items = reset ? page.items : self.items + fresh
                self.exhausted = page.items.count < Self.pageSize || fresh.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                if reset { self.items = [] }
                self.failure = error.localizedDescription
            }
            self.loading = false
        }
    }
}
