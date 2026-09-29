import Foundation
import Observation
import OrbitlDomain

@MainActor
@Observable
final class ChatViewModel {
    let chatId: String
    let currentUserId: String
    private(set) var messages: [Message] = []
    var draft = ""
    var error: OrbitlError?
    private(set) var stickToBottom = true

    private let repository: any MessageRepository
    private var watch: Task<Void, Never>?

    init(chatId: String, currentUserId: String, messages: any MessageRepository) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = messages
    }

    func activate() {
        guard watch == nil else { return }
        watch = Task {
            for await page in repository.messages(chatId: chatId) {
                messages = page
            }
        }
    }

    func loadLatest() async {
        do {
            try await repository.fetchLatest(chatId: chatId)
            error = nil
        } catch let failure as OrbitlError {
            error = failure
        } catch {
            error = .unknown
        }
    }

    func loadOlder() async {
        stickToBottom = false
        do {
            try await repository.loadOlder(chatId: chatId)
        } catch let failure as OrbitlError {
            error = failure
        } catch {
            error = .unknown
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        stickToBottom = true
        do {
            try await repository.send(text: text, chatId: chatId)
            error = nil
        } catch let failure as OrbitlError {
            draft = text
            error = failure
        } catch {
            draft = text
            error = .unknown
        }
    }

    func retry(id: String) async {
        do {
            try await repository.retry(messageId: id)
        } catch let failure as OrbitlError {
            error = failure
        } catch {
            error = .unknown
        }
    }
}
