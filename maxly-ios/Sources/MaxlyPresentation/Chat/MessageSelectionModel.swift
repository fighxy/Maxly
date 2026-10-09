import Foundation
import Observation
import MaxlyDomain

/// Режим выбора нескольких сообщений ленты: «Выбрать» в меню сообщения, касания отмечают,
/// внизу «Копировать», «Переслать», «Удалить». Правила удаления, порядок пересылки и формат
/// копирования — `MessageSelectionRules` (общие сценарии `test-fixtures/selection`). Диалог
/// удаления строит ядро (`deletePlan`, то же правило); своё правило — пока ядро не ответило
/// или если источник его не умеет.
@MainActor
@Observable
public final class MessageSelectionModel {
    /// Подтверждение удаления выбранного.
    public struct DeleteRequest: Identifiable, Hashable, Sendable {
        public let id = UUID()
        /// Локальные id сообщений, все одним запросом.
        public var messageIds: [String]
        public var options: MessageSelectionRules.DeleteOptions

        public var title: String {
            messageIds.count == 1 ? "Удалить сообщение?" : "Удалить \(MessageSelectionModel.countLabel(messageIds.count))?"
        }
    }

    /// Режим включён (даже если всё выбранное уже сняли).
    public private(set) var isActive = false
    /// Выбранные id в порядке выбора.
    public private(set) var selectedIds: [String] = []
    /// Открытое подтверждение удаления.
    public var deleteRequest: DeleteRequest?
    /// Сообщения, которые пересылаются: открыт выбор чатов.
    public var forwardBatch: [Message]?
    public private(set) var isForwarding = false

    /// Тип чата и права — экран ставит их, когда узнаёт.
    @ObservationIgnored public var chatType: ChatType = .private
    /// Аккаунт — владелец или админ. Без прав от ядра (`canDeleteOthers`): в канале право
    /// писать значит админа, в группе роль неизвестна (`false`).
    @ObservationIgnored public var isAdmin = false
    /// Права от ядра (`chatRights`); `nil` — не пришли, решает `isAdmin`.
    @ObservationIgnored public var coreAdmin: Bool?
    /// `edit-timeout` сервера. Пока ядро его не отдало — `.unknown`: своё отправленное
    /// удаляется у всех без срока.
    @ObservationIgnored public var editTimeout: MessageSelectionRules.EditTimeout = .unknown
    /// Диалог удаления от ядра для набора выбранных id.
    private var corePlan: (ids: Set<String>, options: MessageSelectionRules.DeleteOptions)?
    @ObservationIgnored private var planTask: Task<Void, Never>?
    /// Имя собеседника личного чата (для копирования его сообщений, если автор неизвестен).
    @ObservationIgnored public var peerName: String?
    @ObservationIgnored public var timeZone: TimeZone = .current
    @ObservationIgnored public var now: () -> Date = Date.init

    /// Короткое уведомление («Скопировано», «Переслано…»).
    @ObservationIgnored public var onNotice: ((String) -> Void)?
    /// Ошибка запроса.
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?
    /// Сообщения удалены: экран убирает ответ на них и т. п.
    @ObservationIgnored public var onDeleted: (([String]) -> Void)?

    public let chatId: String
    public let currentUserId: String
    @ObservationIgnored private let repository: any MessageRepository

    public init(chatId: String, currentUserId: String, repository: any MessageRepository) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.repository = repository
    }

    // MARK: Выбор

    /// Можно ли выбрать сообщение: всё, кроме служебного о закрепе.
    public func canSelect(_ message: Message) -> Bool {
        message.content.pin == nil
    }

    /// «Выбрать» в меню сообщения: режим включается с ним.
    public func begin(with message: Message) {
        guard canSelect(message) else { return }
        isActive = true
        if !selectedIds.contains(message.id) { selectedIds.append(message.id) }
        refreshPlan()
    }

    /// Касание пузыря в режиме выбора.
    public func toggle(_ message: Message) {
        guard isActive, canSelect(message) else { return }
        if let index = selectedIds.firstIndex(of: message.id) {
            selectedIds.remove(at: index)
        } else {
            selectedIds.append(message.id)
        }
        refreshPlan()
    }

    public func isSelected(_ id: String) -> Bool {
        selectedIds.contains(id)
    }

    /// «Отмена», уход из чата, выполненное действие.
    public func cancel() {
        isActive = false
        selectedIds = []
        planTask?.cancel()
        corePlan = nil
        deleteRequest = nil
        forwardBatch = nil
    }

    /// Выбранные сообщения, ещё живые в ленте, от старых к новым.
    public func selected(in messages: [Message]) -> [Message] {
        let ids = Set(selectedIds)
        return messages.filter { ids.contains($0.id) }.sorted(by: Self.chronological)
    }

    /// Шапка режима: «Выбрано: N».
    public func title(in messages: [Message]) -> String {
        "Выбрано: \(selected(in: messages).count)"
    }

    // MARK: Удаление

    public var context: MessageSelectionRules.ChatContext {
        MessageSelectionRules.ChatContext(id: chatId, type: chatType, isAdmin: coreAdmin ?? isAdmin)
    }

    func item(_ message: Message) -> MessageSelectionRules.Item {
        MessageSelectionRules.Item(
            id: message.id,
            isOwn: message.authorId == currentUserId,
            isSent: message.status == .sent && message.serverId != nil,
            time: message.timestamp
        )
    }

    /// Для панели внизу: ответ ядра на текущий выбор, пока его нет — своё правило.
    public func deleteOptions(in messages: [Message]) -> MessageSelectionRules.DeleteOptions {
        let chosen = selected(in: messages)
        if let corePlan, corePlan.ids == Set(chosen.map(\.id)) { return corePlan.options }
        return localOptions(chosen)
    }

    /// Диалог удаления этих сообщений: правило ядра, источник без него — своё.
    public func deletePlan(for chosen: [Message]) async -> MessageSelectionRules.DeleteOptions {
        guard !chosen.isEmpty,
              let options = await repository.deletePlan(messageIds: chosen.map(\.id), chatId: chatId)
        else { return localOptions(chosen) }
        return options
    }

    func localOptions(_ chosen: [Message]) -> MessageSelectionRules.DeleteOptions {
        MessageSelectionRules.deleteOptions(chosen.map(item), in: context, timeout: editTimeout, now: now())
    }

    /// «Удалить» внизу: открыть подтверждение, если удалить можно. Начальное положение
    /// переключателя «у всех» — от ядра (`forEveryoneByDefault`).
    public func requestDelete(in messages: [Message]) async {
        let chosen = selected(in: messages)
        guard !chosen.isEmpty else { return }
        let options = await deletePlan(for: chosen)
        guard options.canDelete, Set(selected(in: messages).map(\.id)) == Set(chosen.map(\.id)) else { return }
        deleteRequest = DeleteRequest(messageIds: chosen.map(\.id), options: options)
    }

    /// Выбор изменился: спросить ядро заново (панель включает «Удалить» по его ответу).
    private func refreshPlan() {
        planTask?.cancel()
        let ids = selectedIds
        guard !ids.isEmpty else {
            corePlan = nil
            return
        }
        planTask = Task { [weak self, repository, chatId] in
            let options = await repository.deletePlan(messageIds: ids, chatId: chatId)
            guard !Task.isCancelled, let self, self.selectedIds == ids else { return }
            self.corePlan = options.map { (Set(ids), $0) }
        }
    }

    /// Удалить одним запросом. «Избранное» стирается на сервере целиком (как одиночное
    /// удаление), канал с правами — только у всех.
    public func confirmDelete(_ request: DeleteRequest, forEveryone: Bool) async {
        deleteRequest = nil
        let everywhere = context.isSavedMessages || request.options.forcesForEveryone
            || (request.options.showsForEveryone && forEveryone)
        cancel()
        do {
            let failed = try await repository.deleteSelection(messageIds: request.messageIds, chatId: chatId, forEveryone: everywhere)
            onDeleted?(request.messageIds.filter { !failed.contains($0) })
            // Сервер отказал части выбранного: они остаются в ленте.
            if !failed.isEmpty {
                onNotice?("Не удалось удалить: \(Self.countLabel(failed.count))")
            }
        } catch {
            if error != .cancelled { onError?(error) }
        }
    }

    // MARK: Пересылка

    /// Переслать можно, если всё выбранное принято сервером.
    public func canForward(in messages: [Message]) -> Bool {
        let chosen = selected(in: messages)
        return !chosen.isEmpty && chosen.allSatisfy { $0.status == .sent && $0.serverId != nil && $0.content.call == nil }
    }

    public func requestForward(in messages: [Message]) {
        guard canForward(in: messages) else { return }
        forwardBatch = selected(in: messages)
    }

    /// Один запрос на сообщение на чат: комментарий первым, затем от старых к новым.
    /// Возвращает, сколько запросов прошло.
    @discardableResult
    public func forward(_ batch: [Message], to targets: [String], comment: String? = nil) async -> Int {
        forwardBatch = nil
        guard !batch.isEmpty, !targets.isEmpty else { return 0 }
        cancel()
        isForwarding = true
        defer { isForwarding = false }
        let byId = Dictionary(batch.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let plan = MessageSelectionRules.forwardPlan(messages: batch.map { ($0.id, $0.timestamp) }, targets: targets, comment: comment)
        var done = 0
        for step in plan {
            do {
                switch step {
                case let .comment(target, text):
                    try await repository.send(text: text, chatId: target, replyTo: nil)
                case let .message(target, id):
                    guard let message = byId[id] else { continue }
                    try await repository.forward(messageId: message.serverId ?? message.id, from: chatId, to: target)
                }
                done += 1
            } catch {
                if error != .cancelled { onError?(error) }
                return done
            }
        }
        let chats = Set(targets).count
        onNotice?(batch.count == 1 && chats == 1
            ? "Сообщение переслано"
            : "Переслано: \(Self.countLabel(batch.count))" + (chats > 1 ? " в \(chats) \(Self.plural(chats, "чат", "чата", "чатов"))" : ""))
        return done
    }

    // MARK: Копирование

    /// Текст для буфера: одно сообщение — его текст, несколько — блоки с именем и временем.
    public func copyText(in messages: [Message]) -> String {
        let items = selected(in: messages).map { message in
            MessageSelectionRules.CopyItem(
                id: message.serverId ?? message.id,
                time: message.timestamp,
                authorName: authorName(of: message),
                text: message.displayText,
                placeholder: MessageSelectionRules.placeholder(for: message.content.previewMedia)
            )
        }
        return MessageSelectionRules.copyText(items, timeZone: timeZone)
    }

    /// «Копировать» внизу: текст уходит в [pasteboard], режим закрывается.
    public func copy(in messages: [Message], pasteboard: (String) -> Void) {
        let text = copyText(in: messages)
        guard !text.isEmpty else { return }
        pasteboard(text)
        cancel()
        onNotice?("Скопировано")
    }

    func authorName(of message: Message) -> String {
        let name = message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if message.authorId == currentUserId { return "Вы" }
        if chatType == .private, let peerName, !peerName.isEmpty { return peerName }
        return ""
    }

    // MARK: Общее

    nonisolated static func chronological(_ lhs: Message, _ rhs: Message) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return MessageSelectionRules.idOrder(lhs.serverId ?? lhs.id, rhs.serverId ?? rhs.id)
    }

    /// «1 сообщение», «3 сообщения», «11 сообщений».
    public nonisolated static func countLabel(_ count: Int) -> String {
        "\(count) \(plural(count, "сообщение", "сообщения", "сообщений"))"
    }

    nonisolated static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tens = count % 100
        let units = count % 10
        if (11...14).contains(tens) { return many }
        if units == 1 { return one }
        if (2...4).contains(units) { return few }
        return many
    }
}
