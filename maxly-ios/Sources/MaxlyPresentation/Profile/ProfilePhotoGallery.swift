import Foundation
import Observation
import MaxlyDomain

/// Фото профиля в просмотре: текущее и, у человека, прошлые фото с сервера (код 39).
///
/// Первым идёт текущее фото, за ним история страницами по мере листания. «N из M» считается
/// от `total`: текущее плюс то, сколько фото знает сервер. Фото истории с тем же оригиналом,
/// что у текущего, второй раз не показывается.
@MainActor
@Observable
public final class ProfilePhotoGallery: Identifiable {
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String
        /// Что пробовать по порядку: оригинал, потом размеры сервера.
        public let candidates: [URL]

        public init(id: String, candidates: [URL]) {
            self.id = id
            self.candidates = candidates
        }
    }

    public typealias Loader = @Sendable (_ from: Int) async throws(MaxlyError) -> ProfilePhotoPage

    public private(set) var items: [Item]
    /// Всего фото с учётом ещё не загруженных; не меньше, чем `items.count`.
    public var total: Int { max(items.count, knownTotal) }
    public private(set) var isLoading = false

    @ObservationIgnored private let loader: Loader?
    @ObservationIgnored private let idPrefix: String
    @ObservationIgnored private var nextFrom = 0
    @ObservationIgnored private var finished: Bool
    @ObservationIgnored private var skipped = 0
    @ObservationIgnored private var serverTotal = 0
    @ObservationIgnored private var seen: Set<URL>
    /// Дозагрузка, когда до конца осталось столько фото.
    public static let preload = 3

    /// `current` — текущее фото (его id — id плитки для полёта). Без `loader` — только оно.
    public init(current: Item, idPrefix: String, loader: Loader?) {
        items = [current]
        self.idPrefix = idPrefix
        self.loader = loader
        finished = loader == nil
        seen = Set(current.candidates.prefix(1))
    }

    private var knownTotal: Int { serverTotal == 0 ? 0 : 1 + serverTotal - skipped }

    public func candidates(for id: String) -> [URL] {
        items.first { $0.id == id }?.candidates ?? []
    }

    /// Открыто фото `id`: если до конца близко, грузится следующая страница.
    public func shown(_ id: String) async {
        guard let index = items.firstIndex(where: { $0.id == id }), items.count - 1 - index < Self.preload else { return }
        await loadMore()
    }

    public func loadMore() async {
        guard let loader, !finished, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let page: ProfilePhotoPage
        do {
            page = try await loader(nextFrom)
        } catch {
            // Отказ не повторяется по кругу: листается то, что уже есть.
            Log.warning(.chats, "История фото не загрузилась: \(error)")
            finished = true
            return
        }
        nextFrom += page.photos.count
        if page.total > 0 { serverTotal = page.total }
        for (offset, photo) in page.photos.enumerated() {
            guard seen.insert(photo.url).inserted else {
                skipped += 1
                continue
            }
            let key = photo.id.isEmpty ? "n\(nextFrom - page.photos.count + offset)" : photo.id
            items.append(Item(id: "\(idPrefix)-\(key)", candidates: photo.candidates))
        }
        if page.photos.isEmpty || (serverTotal > 0 && nextFrom >= serverTotal) {
            finished = true
        }
    }
}
