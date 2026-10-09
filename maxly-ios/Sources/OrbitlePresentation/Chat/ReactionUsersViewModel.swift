import Foundation
import Observation
import OrbitleDomain

/// Список «Кто отреагировал» для одного сообщения, с отбором по реакции.
@MainActor
@Observable
public final class ReactionUsersViewModel: Identifiable {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    public nonisolated let id: String
    public let message: Message
    public private(set) var state: State = .loading
    public private(set) var users: [ReactionUser] = []
    /// Показать только поставивших эту реакцию. `nil` — всех.
    public var filter: String?

    @ObservationIgnored private let repository: any MessageRepository

    public init(message: Message, repository: any MessageRepository) {
        self.id = message.id
        self.message = message
        self.repository = repository
    }

    /// Вкладки отбора: реакции сообщения в его порядке, с числом.
    public var tabs: [MessageReaction] { message.content.reactions }

    public var visible: [ReactionUser] {
        guard let filter else { return users }
        return users.filter { $0.emoji == filter }
    }

    public var title: String {
        let total = message.content.reactions.total
        return total > 0 ? "Реакции: \(ReactionPalette.countText(total))" : "Реакции"
    }

    public var emptyText: String? {
        state == .loaded && visible.isEmpty ? "Никто не отреагировал" : nil
    }

    public func load() async {
        state = .loading
        do {
            users = try await repository.reactionUsers(messageId: message.id)
            state = .loaded
        } catch {
            guard error != .cancelled else { return }
            state = .failed("Не удалось загрузить список")
        }
    }

    /// Имя строки: без профиля — «Пользователь» и id.
    public static func name(of user: ReactionUser) -> String {
        let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Пользователь \(user.userId)" : name
    }
}
