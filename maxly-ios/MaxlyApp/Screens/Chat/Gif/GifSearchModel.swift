import Foundation
import Observation
import MaxlyData
import MaxlyDomain

/// Настройки поиска gifka.me в приложении.
enum GifkaSettings {
    /// «Поиск GIF (gifka.me)»: по умолчанию выключен.
    static let enabledKey = "gifkaSearchEnabled"

    /// Ключ API из сборки (Info.plist `GifkaAPIKey`, заполняется на CI). Пусто — без ключа.
    static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "GifkaAPIKey") as? String
    }

    static let siteURL = URL(string: "https://gifka.me")!

    /// «Пожаловаться» на долгом нажатии по найденной гифке или стикеру.
    static let reportsEnabled = true

    /// Текст ошибки для человека: сеть, лимит запросов или ответ сервиса.
    static func message(_ error: Error) -> String {
        if let error = error as? GifkaError, case .http(429) = error {
            return "gifka.me просит подождать. Попробуйте через минуту."
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Нет соединения с интернетом"
            case .timedOut:
                return "gifka.me не ответил вовремя"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// Выдача gifka.me одного вида (гифки или стикеры): тренды при пустом запросе, поиск с
/// задержкой при вводе, следующая страница по мере прокрутки.
@MainActor
@Observable
final class GifSearchModel {
    let type: GifkaClient.MediaType
    private(set) var items: [GifkaMedia] = []
    private(set) var loading = false
    private(set) var failure: String?
    private(set) var exhausted = false
    /// Запрос, по которому показана или грузится выдача.
    private(set) var query = ""

    @ObservationIgnored let client: GifkaClient
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Номер последнего запроса: ответ устаревшего не трогает выдачу и индикатор загрузки.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var started = false
    private static let pageSize = 30
    private static let debounce: Duration = .milliseconds(400)

    init(type: GifkaClient.MediaType, client: GifkaClient) {
        self.type = type
        self.client = client
    }

    /// Показать выдачу по запросу `text`. Тот же запрос второй раз ничего не грузит.
    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !started || trimmed != query else { return }
        let first = !started
        started = true
        query = trimmed
        // Первая выдача и сброс запроса — сразу, ввод — после паузы.
        load(reset: true, delay: !first && !trimmed.isEmpty)
    }

    /// Следующая страница. После ошибки — только по «Повторить» (`retrying`), а не на каждом
    /// показе последней ячейки.
    func loadMore(retrying: Bool = false) {
        guard started, !loading, !exhausted, failure == nil || retrying, !items.isEmpty else { return }
        load(reset: false, delay: false)
    }

    func retry() {
        started = true
        load(reset: true, delay: false)
    }

    private func load(reset: Bool, delay: Bool) {
        task?.cancel()
        generation += 1
        let ticket = generation
        let text = query
        let offset = reset ? 0 : items.count
        let client = client
        let type = type
        // Сразу, ещё до паузы ввода: пока запрос ждёт, следующая страница старого не грузится.
        loading = true
        failure = nil
        task = Task { [weak self] in
            if delay { try? await Task.sleep(for: Self.debounce) }
            guard let self, self.generation == ticket else { return }
            do {
                let page = text.isEmpty
                    ? try await client.trending(type: type, limit: Self.pageSize, offset: offset)
                    : try await client.search(text, type: type, limit: Self.pageSize, offset: offset)
                guard self.generation == ticket else { return }
                let known = Set(reset ? [] : self.items.map(\.id))
                let fresh = page.items.filter { !known.contains($0.id) }
                self.items = reset ? page.items : self.items + fresh
                self.exhausted = page.items.count < Self.pageSize || fresh.isEmpty
            } catch {
                guard self.generation == ticket else { return }
                if reset { self.items = [] }
                self.failure = GifkaSettings.message(error)
            }
            self.loading = false
        }
    }
}

/// Раздел «GIF» панели на месте клавиатуры: один запрос на гифки и стикеры gifka.me.
/// Живёт с экраном чата: открыв панель снова, человек видит ту же выдачу и тот же запрос.
@MainActor
@Observable
final class GifPanelModel {
    enum Section: String, CaseIterable, Identifiable {
        case gifs, stickers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gifs: "GIF"
            case .stickers: "Стикеры gifka.me"
            }
        }
    }

    var section: Section = .gifs {
        didSet { if section != oldValue { active.search(query) } }
    }
    var query = "" {
        didSet { if query != oldValue { active.search(query) } }
    }
    /// Поле поиска в фокусе: клавиатура открыта, панель ниже, чтобы выдача осталась видна.
    var isSearching = false

    let gifs: GifSearchModel
    let stickers: GifSearchModel
    @ObservationIgnored let client: GifkaClient
    /// Показы, выбор и отправка для gifka.me (`POST /v1/pingback`); без ключа `nil`.
    @ObservationIgnored let pingback: GifkaPingback?

    init(apiKey: String? = GifkaSettings.apiKey) {
        let client = GifkaClient(apiKey: apiKey)
        self.client = client
        pingback = GifkaPingback(client: client)
        gifs = GifSearchModel(type: .gif, client: client)
        stickers = GifSearchModel(type: .sticker, client: client)
    }

    var active: GifSearchModel {
        section == .gifs ? gifs : stickers
    }

    /// Раздел открыт: выдача по текущему запросу (тренды, если он пуст).
    func appear() {
        active.search(query)
    }

    /// Панель закрылась: клавиатура поиска убрана, накопленные показы ушли.
    func disappear() {
        isSearching = false
        let pingback = pingback
        Task { await pingback?.flush() }
    }
}

/// Отправка выбранных гифок по очереди: файл GIF качается с gifka.me и уходит фото.
/// Несколько нажатий подряд отправляют все гифки по порядку, а не только последнюю.
/// Неудачная остаётся первой с ошибкой: «Повторить» или убрать, тогда пойдёт следующая.
@MainActor
@Observable
final class GifSendQueue {
    struct Item: Identifiable {
        let id = UUID()
        let media: GifkaMedia
        let client: GifkaClient
        var failure: String?
    }

    private(set) var items: [Item] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var send: (@MainActor (AttachmentDraft) async -> Bool)?

    /// Гифка, которая качается или не ушла.
    var current: Item? { items.first }
    /// Сколько ждут за ней.
    var waiting: Int { max(0, items.count - 1) }

    func enqueue(_ media: GifkaMedia, client: GifkaClient, send: @escaping @MainActor (AttachmentDraft) async -> Bool) {
        self.send = send
        items.append(Item(media: media, client: client))
        pump()
    }

    func retry() {
        guard !items.isEmpty, items[0].failure != nil else { return }
        items[0].failure = nil
        pump()
    }

    /// Отменить загрузку текущей или убрать неудачную; следующая пойдёт сама.
    func dismissCurrent() {
        task?.cancel()
        task = nil
        if !items.isEmpty { items.removeFirst() }
        pump()
    }

    private func pump() {
        guard task == nil, let item = items.first, item.failure == nil, let send else { return }
        task = Task { [weak self] in
            do {
                let data = try await item.client.downloadGIF(item.media)
                try Task.checkCancellation()
                let draft = try MediaExporter.draft(gifData: data)
                let sent = await send(draft)
                guard let self, !Task.isCancelled, self.items.first?.id == item.id else { return }
                self.task = nil
                if sent {
                    self.items.removeFirst()
                    // Событие отправки для gifka.me: только id медиа.
                    let client = item.client
                    let id = item.media.id
                    Task.detached { await client.pingback([GifkaEvent(mediaId: id, kind: .send)]) }
                    self.pump()
                } else {
                    self.items[0].failure = "Не удалось отправить сообщение"
                }
            } catch {
                // Отменённая («крестик») уже убрана из очереди.
                guard let self, !Task.isCancelled, self.items.first?.id == item.id else { return }
                self.task = nil
                self.items[0].failure = GifkaSettings.message(error)
            }
        }
    }
}
