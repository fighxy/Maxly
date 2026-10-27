import Foundation
import Observation
import MaxlyDomain

/// Закрепы открытого чата для шапки: служебное сообщение `pin` в ленте, пока список 241 не
/// пришёл, затем сам список («2 из 5»), пуши закрепов (база их не хранит), закрепить, открепить
/// и снять все. Ошибки и уведомления показывает экран чата (`onError`, `onNotice`).
@MainActor
@Observable
public final class ChatPinsModel {
    public let chatId: String
    /// Закреп, который видит шапка чата. `nil` — закрепа нет.
    /// Пока список 241 не пришёл, это служебное сообщение `pin` в ленте.
    public private(set) var pinned: (id: String, text: String)?
    /// Список закрепов 241, от нового к старому. Пустой, пока его не загрузили.
    public private(set) var list = PinBar()
    /// Список 241 уже ответил: шапка смотрит на `list`, а не на служебное сообщение.
    public private(set) var fromList = false
    /// Лист со всеми закрепами.
    public var listShown = false
    /// Сообщение, которое спрашивают, как закрепить.
    public var prompt: Message?
    /// Живая лента чата: из неё служебное сообщение закрепа и текст закрепа из пуша.
    @ObservationIgnored public var live: () -> [Message] = { [] }
    /// Перейти к сообщению закрепа.
    @ObservationIgnored public var onFocus: ((String) -> Void)?
    @ObservationIgnored public var onNotice: ((String) -> Void)?
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private var override: PinNotice?
    @ObservationIgnored private var baselineId: String?
    @ObservationIgnored private var hub: PinHub?
    @ObservationIgnored private var watch: Task<Void, Never>?

    public init(chatId: String, repository: any MessageRepository) {
        self.chatId = chatId
        self.repository = repository
    }

    /// Пуши закрепов. База их не хранит, поэтому чат слушает их сам.
    public func attach(_ hub: PinHub?) {
        self.hub = hub
    }

    /// Шапка: текущий закреп и «2 из 5», когда их несколько.
    public var banner: (id: String, text: String, counter: String?)? {
        if fromList {
            guard let current = list.current else { return nil }
            return (current.messageId, current.text, list.counter)
        }
        guard let pinned else { return nil }
        return (pinned.id, pinned.text, nil)
    }

    func stopWatch() {
        watch?.cancel()
        watch = nil
    }

    private func show(_ failure: MaxlyError) {
        onError?(failure)
    }

    private func showNotice(_ text: String) {
        onNotice?(text)
    }

    /// Меню закрепа: в диалоге «Только у меня», в группе «Уведомить участников».
    public func request(_ message: Message) {
        guard message.status == .sent, Int64(message.id) != nil, !message.content.isService else { return }
        prompt = message
    }

    public func confirm(forMe: Bool, notify: Bool) async {
        let message = prompt
        prompt = nil
        guard let message else { return }
        await pin(message, forMe: forMe, notify: notify)
    }

    public func pin(_ message: Message, forMe: Bool = false, notify: Bool = true) async {
        guard message.status == .sent, Int64(message.id) != nil, !message.content.isService else { return }
        let preview = message.replySnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = preview.isEmpty ? "Сообщение" : preview
        do {
            try await repository.updatePin(chatId: chatId, action: "pin", messageIds: [message.id], forMe: forMe, notify: notify)
            var bar = list
            bar.apply(action: "pin", messageId: message.id, text: title)
            list = bar
            fromList = true
            showNotice("Сообщение закреплено")
        } catch let failure as MaxlyError where failure == .invalidRequest && !forMe && notify {
            await pinLegacy(message, title: title)
        } catch let failure as MaxlyError {
            show(failure)
        } catch {
            show(.unknown)
        }
    }

    /// Opcode 55: один закреп, если список 242 источнику недоступен.
    private func pinLegacy(_ message: Message, title: String) async {
        baselineId = live().reversed().first { $0.content.pin != nil }?.id
        do {
            try await repository.pin(chatId: chatId, messageId: message.id)
            override = PinNotice(messageId: message.id, preview: title)
            applyState()
            showNotice("Сообщение закреплено")
        } catch {
            show(error)
        }
    }

    public func unpin() async {
        if fromList, let id = list.current?.messageId {
            await unpin(messageId: id)
            return
        }
        baselineId = live().reversed().first { $0.content.pin != nil }?.id
        do {
            try await repository.pin(chatId: chatId, messageId: "0")
            override = PinNotice(messageId: nil, preview: "")
            applyState()
            showNotice("Закреп снят")
        } catch {
            show(error)
        }
    }

    public func unpin(messageId: String) async {
        let id = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        do {
            try await repository.updatePin(chatId: chatId, action: "unpin", messageIds: [id], forMe: false, notify: true)
            var bar = list
            bar.apply(action: "unpin", messageId: id)
            list = bar
            fromList = true
            showNotice("Закреп снят")
        } catch {
            show(error)
        }
    }

    public func unpinAll() async {
        do {
            try await repository.updatePin(chatId: chatId, action: "unpinAll", messageIds: [], forMe: false, notify: true)
            list = PinBar()
            fromList = true
            showNotice("Закрепы сняты")
        } catch {
            show(error)
        }
    }

    /// Касание плашки: открыть текущий закреп и показать следующий более старый.
    public func cycle() {
        if fromList {
            var bar = list
            guard let id = bar.advance() else { return }
            list = bar
            onFocus?(id)
            return
        }
        if let pinned { onFocus?(pinned.id) }
    }

    func startWatch() {
        watch?.cancel()
        guard let hub else { return }
        let stream = hub.pins()
        watch = Task { [weak self] in
            for await push in stream {
                guard let self, !Task.isCancelled, push.chatId == self.chatId else { continue }
                await self.applyPush(push)
            }
        }
    }

    private func applyPush(_ push: PinPush) async {
        if push.count == 0 || push.action == "unpinAll" {
            list = PinBar()
            fromList = true
            return
        }
        if !fromList, push.action == "unpin", push.messageId != pinned?.id { return }
        var bar = fromList ? list : PinBar(pins: pinned.map { [ChatPin(messageId: $0.id, text: $0.text)] } ?? [])
        let text = live().first { $0.id == push.messageId || $0.serverId == push.messageId }?.replySnippet ?? ""
        bar.apply(action: push.action, messageId: push.messageId, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        list = bar
        fromList = true
    }

    func applyState() {
        // Список 241 уже на экране: служебное сообщение его не затирает.
        guard !fromList else { return }
        let latestId = live().reversed().first { $0.content.pin != nil }?.id
        if override != nil, latestId != baselineId {
            override = nil
            baselineId = nil
        }
        if let override = override {
            if let id = override.messageId, !id.isEmpty {
                pinned = (id, override.preview.isEmpty ? "Сообщение" : override.preview)
            } else {
                pinned = nil
            }
            return
        }
        pinned = Self.pinnedNotice(in: live())
    }

    static func pinnedNotice(in messages: [Message]) -> (id: String, text: String)? {
        for message in messages.reversed() {
            guard let pin = message.content.pin else { continue }
            guard let id = pin.messageId, !id.isEmpty else { return nil }
            return (id, pin.preview.isEmpty ? "Сообщение" : pin.preview)
        }
        return nil
    }
}
