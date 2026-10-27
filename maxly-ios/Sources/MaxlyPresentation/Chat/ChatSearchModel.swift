import Foundation
import Observation
import MaxlyDomain

/// Поиск по сообщениям открытого чата (лист поиска). Ответ старого запроса экран не меняет:
/// новый запрос и закрытие листа отменяют его.
@MainActor
@Observable
public final class ChatSearchModel {
    public let chatId: String
    public private(set) var hits: [FoundMessage] = []
    public private(set) var busy = false
    public private(set) var error: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let repository: any MessageRepository

    public init(chatId: String, repository: any MessageRepository) {
        self.chatId = chatId
        self.repository = repository
    }

    /// Закрытие и очистка поиска отменяют право старого ответа менять экран.
    public func reset() {
        generation += 1
        hits = []
        busy = false
        error = nil
    }

    public func search(_ query: String, debounce: Duration = .zero) async {
        reset()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !Task.isCancelled else { return }
        let current = generation
        busy = true
        defer { if current == generation { busy = false } }
        do {
            if debounce > .zero { try await Task.sleep(for: debounce) }
            guard current == generation, !Task.isCancelled else { return }
            let found = try await repository.searchInChat(chatId: chatId, query: term)
            guard current == generation, !Task.isCancelled else { return }
            hits = found
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            self.error = (error as? MaxlyError)?.userMessage ?? "Не удалось выполнить поиск"
        }
    }
}
