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
    /// Текст в поле ввода. Сохраняется черновиком с короткой задержкой и при уходе с экрана.
    public var draft = "" {
        didSet {
            guard draft != oldValue, !isRestoringDraft else { return }
            scheduleDraftSave()
        }
    }
    public private(set) var error: OrbitlError?
    public private(set) var stickToBottom = true

    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let drafts: (any ChatDraftStore)?
    @ObservationIgnored private let draftDelay: Duration
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var draftSave: Task<Void, Never>?
    @ObservationIgnored private var isRestoringDraft = false
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    /// Последний текст, отданный хранилищу: не пишем одно и то же дважды.
    @ObservationIgnored private var savedDraft: String?

    public init(
        chatId: String,
        currentUserId: String,
        messages: any MessageRepository,
        drafts: (any ChatDraftStore)? = nil,
        draftDelay: Duration = .milliseconds(500)
    ) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = messages
        self.drafts = drafts
        self.draftDelay = draftDelay
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
        if let drafts {
            let chatId = chatId
            Task { [weak self] in
                let saved = await drafts.draft(chatId: chatId)
                guard let self, let saved, self.draft.isEmpty else { return }
                self.savedDraft = saved
                self.isRestoringDraft = true
                self.draft = saved
                self.isRestoringDraft = false
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
        flushDraft()
    }

    /// Сохранить черновик сразу, не дожидаясь паузы в наборе.
    public func flushDraft() {
        draftSave?.cancel()
        draftSave = nil
        persistDraft()
    }

    private func scheduleDraftSave() {
        guard drafts != nil else { return }
        draftSave?.cancel()
        let delay = draftDelay
        draftSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }
    }

    private func persistDraft() {
        guard let drafts else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != (savedDraft ?? "") else { return }
        savedDraft = text
        let chatId = chatId
        // Записи идут цепочкой: иначе поздний пустой черновик мог бы лечь раньше раннего.
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            await drafts.saveDraft(text, chatId: chatId)
        }
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
