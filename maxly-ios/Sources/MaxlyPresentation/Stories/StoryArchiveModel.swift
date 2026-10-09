import Foundation
import Observation
import MaxlyDomain

/// «Мои истории»: архив своих историй страницами по 30 (`STORIES_HISTORY_GET_BY_OWNER_ID` 219).
/// Первая страница — без курсора, следующие — с курсором прошлого ответа; пустой курсор — конец.
@MainActor
@Observable
public final class StoryArchiveModel {
    public enum State: Equatable, Sendable {
        case loading
        /// Историй нет: «Место для воспоминаний».
        case empty
        case ready
        /// Первая страница не загрузилась.
        case failed(String)
    }

    public static let emptyTitle = "Место для воспоминаний"
    public static let emptyText = "Здесь будут ваши истории, даже когда они исчезнут из ленты."

    public private(set) var state: State = .loading
    /// Истории от новых к старым, без повторов.
    public private(set) var stories: [Story] = []
    /// За последней историей есть ещё страница.
    public private(set) var canLoadMore = false
    /// Следующая страница не загрузилась: экран показывает «Повторить».
    public private(set) var pageError: String?

    @ObservationIgnored private let repository: any StoriesRepository
    @ObservationIgnored private var marker = ""
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var started = false

    public init(repository: any StoriesRepository) {
        self.repository = repository
    }

    /// Экран открылся: первая страница, один раз.
    public func activate() async {
        guard !started else { return }
        started = true
        await reload()
    }

    /// Заново с первой страницы (потянуть вниз, «Повторить»).
    public func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if stories.isEmpty { state = .loading }
        do {
            let page = try await repository.archive(marker: "")
            stories = []
            append(page)
            pageError = nil
            state = stories.isEmpty ? .empty : .ready
        } catch {
            if stories.isEmpty {
                state = .failed(error.userMessage ?? "Не удалось загрузить истории")
            } else {
                pageError = error.userMessage ?? "Не удалось загрузить истории"
            }
        }
    }

    /// Экран дошёл до последней истории: следующая страница.
    public func loadMore() async {
        guard canLoadMore, !loading, !marker.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await repository.archive(marker: marker)
            append(page)
            pageError = nil
            state = stories.isEmpty ? .empty : .ready
        } catch {
            pageError = error.userMessage ?? "Не удалось загрузить истории"
        }
    }

    private func append(_ page: StoryArchivePage) {
        var known = Set(stories.map(\.id))
        for story in page.stories where known.insert(story.id).inserted {
            stories.append(story)
        }
        marker = page.isLast ? "" : page.marker
        canLoadMore = !marker.isEmpty && !page.stories.isEmpty
    }
}
