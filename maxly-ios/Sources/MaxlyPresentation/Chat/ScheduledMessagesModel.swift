import Foundation
import Observation
import MaxlyDomain

/// Отложенные сообщения открытого чата: список по времени отправки, новое, правка, отмена и
/// «отправить сейчас». Пуши об отложенных приходят через `ScheduledHub`, база их не хранит.
/// Ошибки и уведомления показывает экран чата (`onError`, `onNotice`).
@MainActor
@Observable
public final class ScheduledMessagesModel {
    public let chatId: String
    /// Отложенные сообщения этого чата, по времени отправки.
    public private(set) var items: [FoundMessage] = []
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private var hub: ScheduledHub?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored public var onNotice: ((String) -> Void)?
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?
    /// Черновик запланирован: поле ввода очищается.
    @ObservationIgnored public var onScheduled: (() -> Void)?

    public init(chatId: String, repository: any MessageRepository) {
        self.chatId = chatId
        self.repository = repository
    }

    public func attach(_ hub: ScheduledHub?) {
        self.hub = hub
    }

    public func schedule(text: String, at date: Date) async {
        do {
            try await repository.schedule(chatId: chatId, text: text, sendAt: date)
            onScheduled?()
            onNotice?("Сообщение запланировано")
            await load()
        } catch {
            onError?(error)
        }
    }

    public func load() async {
        do {
            let found = try await repository.scheduled(chatId: chatId)
            items = found.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        } catch {
            onError?(error)
        }
    }

    public func edit(_ item: FoundMessage, text: String, at date: Date) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            _ = try await repository.editScheduled(chatId: chatId, messageId: item.messageId, text: body, sendAt: date)
            onNotice?("Отложенное изменено")
            await load()
        } catch {
            onError?(error)
        }
    }

    public func cancel(_ item: FoundMessage) async {
        do {
            try await repository.cancelScheduled(chatId: chatId, messageIds: [item.messageId])
            items.removeAll { $0.messageId == item.messageId }
            onNotice?("Отложенное отменено")
        } catch {
            onError?(error)
        }
    }

    /// Отправить отложенное сейчас: время отправки становится текущим.
    public func sendNow(_ item: FoundMessage) async {
        await edit(item, text: item.text, at: Date())
    }

    /// Слушать пуши об отложенных этого чата, пока он открыт.
    func startWatch() {
        watch?.cancel()
        guard let hub else { return }
        let stream = hub.events()
        watch = Task { [weak self] in
            for await push in stream {
                guard let self, !Task.isCancelled, push.chatId == self.chatId else { continue }
                await self.load()
            }
        }
    }

    func stopWatch() {
        watch?.cancel()
        watch = nil
    }
}
