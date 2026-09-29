import Foundation
import Observation
import OrbitlDomain

/// Открытый чат: сообщения из репозитория, черновик, отправка и повтор.
@MainActor
@Observable
public final class ChatViewModel {
    public let chatId: String
    public let currentUserId: String
    public private(set) var messages: [Message] = []
    public var draft = ""
    public private(set) var error: OrbitlError?
    public private(set) var stickToBottom = true

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private var watch: Task<Void, Never>?

    public init(chatId: String, currentUserId: String, messages: any MessageRepository) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = messages
    }

    public var errorMessage: String? { error?.userMessage }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func isOutgoing(_ message: Message) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
    }

    public func activate() {
        guard watch == nil else { return }
        let stream = repository.messages(chatId: chatId)
        watch = Task { [weak self] in
            for await page in stream {
                guard let self else { return }
                self.messages = page
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
    }

    public func loadLatest() async {
        do {
            try await repository.fetchLatest(chatId: chatId)
            error = nil
        } catch {
            show(error)
        }
    }

    public func loadOlder() async {
        stickToBottom = false
        do {
            try await repository.loadOlder(chatId: chatId)
        } catch {
            show(error)
        }
    }

    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        stickToBottom = true
        do {
            try await repository.send(text: text, chatId: chatId)
            error = nil
        } catch {
            draft = text
            show(error)
        }
    }

    public func retry(id: String) async {
        do {
            try await repository.retry(messageId: id)
        } catch {
            show(error)
        }
    }

    private func show(_ failure: OrbitlError) {
        if failure != .cancelled { error = failure }
    }
}
