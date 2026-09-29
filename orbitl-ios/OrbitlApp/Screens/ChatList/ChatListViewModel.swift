import Foundation
import Observation
import OrbitlDomain

@MainActor
@Observable
final class ChatListViewModel {
    private(set) var chats: [Chat] = []
    var error: OrbitlError?

    private let repository: any ChatRepository
    private var watch: Task<Void, Never>?

    init(chats: any ChatRepository) {
        self.repository = chats
    }

    func activate() {
        guard watch == nil else { return }
        watch = Task {
            for await page in repository.chats() {
                chats = page
            }
        }
    }

    func refresh() async {
        do {
            try await repository.refresh()
            error = nil
        } catch let failure as OrbitlError {
            error = failure
        } catch {
            error = .unknown
        }
    }
}
