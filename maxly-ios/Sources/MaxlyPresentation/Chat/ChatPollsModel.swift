import Foundation
import Observation
import MaxlyDomain

/// Опросы открытого чата: голос, несколько ответов, новый опрос и редкая сверка счёта опросов
/// на экране (пуша со счётом нет). Ошибки и уведомления показывает экран чата
/// (`onError`, `onNotice`).
@MainActor
@Observable
public final class ChatPollsModel {
    public let chatId: String
    /// Опросы, голос в которых сейчас в пути: повторное нажатие не шлёт второй голос.
    public private(set) var voting: Set<String> = []
    /// Сервер ответил `poll.already.voted`: больше голос в этот опрос не шлём.
    public private(set) var alreadyVoted: Set<String> = []
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private var refresh: Task<Void, Never>?
    /// Сообщения ленты: из них сверка берёт опросы на экране.
    @ObservationIgnored public var messages: () -> [Message] = { [] }
    /// Перед отправкой опроса: лента возвращается к живой, чтобы он был виден.
    @ObservationIgnored public var beforeSend: (() -> Void)?
    @ObservationIgnored public var onNotice: ((String) -> Void)?
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?
    /// Голос принят: прежняя ошибка над полем ввода уже не о чем.
    @ObservationIgnored public var onSuccess: (() -> Void)?

    /// Пауза между сверками счёта опросов на экране.
    static let refreshInterval: Duration = .seconds(20)

    public init(chatId: String, repository: any MessageRepository) {
        self.chatId = chatId
        self.repository = repository
    }

    /// Голос в опрос можно отправить сейчас.
    public func canVote(in poll: PollContent) -> Bool {
        poll.canVote && !voting.contains(poll.id) && !alreadyVoted.contains(poll.id)
    }

    public func vote(_ message: Message, answerId: String) async {
        guard let poll = message.content.poll, !answerId.isEmpty,
              let serverId = Self.serverId(of: message),
              canVote(in: poll) else { return }
        voting.insert(poll.id)
        defer { voting.remove(poll.id) }
        do {
            let update = try await repository.votePoll(chatId: chatId, messageId: serverId, pollId: poll.id, answerId: answerId)
            await repository.applyPollCounts(chatId: chatId, messageId: message.id, update: update)
            onSuccess?()
        } catch {
            await voteFailed(error, message: message, serverId: serverId, pollId: poll.id)
        }
    }

    public func castVotes(_ message: Message, answerIds: [String]) async {
        let ids = answerIds.filter { !$0.isEmpty }
        guard let poll = message.content.poll, !ids.isEmpty,
              let serverId = Self.serverId(of: message),
              canVote(in: poll) else { return }
        voting.insert(poll.id)
        defer { voting.remove(poll.id) }
        do {
            let update = try await repository.castVotes(chatId: chatId, messageId: serverId, pollId: poll.id, answerIds: ids)
            await repository.applyPollCounts(chatId: chatId, messageId: message.id, update: update)
            onSuccess?()
        } catch {
            await voteFailed(error, message: message, serverId: serverId, pollId: poll.id)
        }
    }

    public func send(title: String, answers: [String]) async {
        let options = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard options.count >= 2 else {
            onError?(.rejected("Нужно хотя бы два ответа"))
            return
        }
        beforeSend?()
        do {
            try await repository.sendPoll(chatId: chatId, title: title, answers: options)
            onNotice?("Опрос отправлен")
        } catch {
            onError?(error)
        }
    }

    /// Сверять счёт опросов на экране, пока чат открыт.
    func startRefresh() {
        refresh?.cancel()
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard let self, !Task.isCancelled else { return }
                await self.refreshVisible()
            }
        }
    }

    func stopRefresh() {
        refresh?.cancel()
        refresh = nil
    }

    /// `poll.already.voted`: голос уже засчитан. Без повтора — свежий опрос с сервера и результаты.
    private func voteFailed(_ failure: MaxlyError, message: Message, serverId: String, pollId: String) async {
        guard failure.isPollAlreadyVoted else {
            onError?(failure)
            return
        }
        onSuccess?()
        alreadyVoted.insert(pollId)
        if let updates = try? await repository.refreshPolls(chatId: chatId, polls: [(serverId, pollId)]),
           let update = updates.first(where: { $0.pollId == pollId || $0.pollId.isEmpty }) {
            await repository.applyPollCounts(chatId: chatId, messageId: message.id, update: update)
        }
        onNotice?(MaxlyError.server(code: MaxlyError.pollAlreadyVotedCode, text: nil).userMessage ?? "")
    }

    private func refreshVisible() async {
        let messages = messages()
        let polls: [(messageId: String, pollId: String)] = messages.compactMap { message in
            guard let poll = message.content.poll, let id = Self.serverId(of: message) else { return nil }
            return (id, poll.id)
        }
        guard !polls.isEmpty else { return }
        do {
            let updates = try await repository.refreshPolls(chatId: chatId, polls: polls)
            for update in updates {
                guard let message = messages.first(where: { $0.content.poll?.id == update.pollId }) else { continue }
                await repository.applyPollCounts(chatId: chatId, messageId: message.id, update: update)
            }
        } catch {
            // Тихий повтор на следующем круге.
        }
    }

    /// Серверный id сообщения опроса; у неотправленного его нет.
    private static func serverId(of message: Message) -> String? {
        message.serverId ?? (Int64(message.id) != nil ? message.id : nil)
    }
}
