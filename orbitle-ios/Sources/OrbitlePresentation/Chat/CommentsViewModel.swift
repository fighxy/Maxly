import Foundation
import Observation
import OrbitleDomain

/// Комментарии одного поста. Отправка не ставится в исходящую очередь.
@MainActor
@Observable
public final class CommentsViewModel {
    public let chatId: String
    public let postId: String
    public private(set) var comments: [Message] = []
    public var draft = ""
    public private(set) var error: OrbitleError?

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private var watch: Task<Void, Never>?

    public init(chatId: String, postId: String, messages: any MessageRepository) {
        self.chatId = chatId
        self.postId = postId
        self.repository = messages
    }

    public var errorMessage: String? { error?.userMessage }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var emptyText: String? {
        comments.isEmpty ? "Пока нет комментариев" : nil
    }

    public func isOutgoing(_ message: Message, currentUserId: String) -> Bool {
        !currentUserId.isEmpty && message.authorId == currentUserId
    }

    public func activate() {
        guard watch == nil else { return }
        let stream = repository.comments(chatId: chatId, postId: postId)
        watch = Task { [weak self] in
            for await page in stream {
                guard let self else { return }
                self.comments = page
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
    }

    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        do {
            try await repository.sendComment(text: text, chatId: chatId, postId: postId)
            error = nil
        } catch {
            draft = text
            if error != .cancelled { self.error = error }
        }
    }
}
