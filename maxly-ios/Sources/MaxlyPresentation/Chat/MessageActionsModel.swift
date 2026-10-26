import Foundation
import Observation
import MaxlyDomain

/// Действия меню одного сообщения: удаление с выбором «у себя / у всех», пересылка, повтор
/// отправки и «Поделиться контактом» из профиля. Ошибки и уведомления показывает экран чата.
@MainActor
@Observable
public final class MessageActionsModel {
    public let chatId: String
    /// Сообщение, для которого открыт выбор «удалить у себя / у всех».
    public var deletionCandidate: Message?
    /// Варианты удаления открытого сообщения (`deletePlan` ядра, как у выбора нескольких).
    public private(set) var deletionOptions: MessageSelectionRules.DeleteOptions?
    /// Сообщение, для которого открыт выбор чата пересылки.
    public var forwardCandidate: Message?
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private let selection: MessageSelectionModel
    /// Сообщение вот-вот удалится: цитата на него снимается с поля ввода.
    @ObservationIgnored public var onWillDelete: ((String) -> Void)?
    @ObservationIgnored public var onSuccess: (() -> Void)?
    @ObservationIgnored public var onNotice: ((String) -> Void)?
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?

    public init(chatId: String, repository: any MessageRepository, selection: MessageSelectionModel) {
        self.chatId = chatId
        self.repository = repository
        self.selection = selection
    }

    /// Меню сообщения → «Удалить»: варианты решает ядро (`deletePlan`), как и для выбора
    /// нескольких. Нельзя удалить вовсе — плашка вместо диалога.
    public func requestDelete(_ message: Message) {
        Task { [weak self] in
            guard let self else { return }
            let options = await selection.deletePlan(for: [message])
            guard options.canDelete || deletesWithoutChoice else {
                onNotice?("Это сообщение нельзя удалить")
                return
            }
            deletionOptions = options
            deletionCandidate = message
        }
    }

    /// «Удалить у всех» — только для своих сообщений, уже принятых сервером.
    /// «Избранное» принадлежит только аккаунту: сообщение удаляется на сервере целиком
    /// (`forMe: false`), и пересланное, и отправленное с другого устройства. Удаление
    /// «у себя» скрыло бы его лишь в этом клиенте.
    public func deletesEverywhere(_ message: Message) -> Bool {
        message.serverId.map { Int64($0) != nil } ?? false
    }

    /// Только «удалить у всех», без выбора (канал с правами).
    public var deletionForcesEveryone: Bool { deletionOptions?.forcesForEveryone == true }

    /// Вариант «удалить у всех» есть; `deletionPrefersEveryone` — он идёт первым.
    public var deletionShowsEveryone: Bool { deletionOptions?.showsForEveryone == true }
    public var deletionPrefersEveryone: Bool { deletionOptions?.forEveryoneByDefault == true }

    /// Удаление из «Избранного»: собеседника нет, поэтому один вариант без выбора.
    public var deletesWithoutChoice: Bool { chatId == Chat.savedMessagesId }

    /// Удаление выбранного сообщения. Сообщение передаётся явно: диалог подтверждения
    /// сбрасывает `deletionCandidate` раньше, чем срабатывает его кнопка.
    public func confirmDelete(_ candidate: Message? = nil, forEveryone: Bool) async {
        guard let message = candidate ?? deletionCandidate else { return }
        deletionCandidate = nil
        onWillDelete?(message.id)
        do {
            try await repository.delete(messageIds: [message.id], chatId: chatId, forEveryone: forEveryone)
            onSuccess?()
        } catch {
            onError?(error)
        }
    }

    public func requestForward(_ message: Message) {
        forwardCandidate = message
    }

    public func forward(to targetChatId: String) async {
        guard let message = forwardCandidate else { return }
        forwardCandidate = nil
        do {
            try await repository.forward(messageId: message.serverId ?? message.id, from: chatId, to: targetChatId)
            onSuccess?()
            onNotice?("Сообщение переслано")
        } catch {
            onError?(error)
        }
    }

    /// «Поделиться контактом» из профиля: карточка `userId` уходит в чат `targetChatId`.
    public func shareContact(userId: String, name: String, to targetChatId: String) async {
        let card = AttachmentDraft(kind: .contact, contactId: userId, contactName: name)
        do {
            try await repository.sendAttachments([card], caption: "", chatId: targetChatId, replyTo: nil)
            onNotice?("Контакт отправлен")
        } catch {
            onError?(error)
        }
    }

    public func retry(id: String) async {
        do {
            try await repository.retry(messageId: id)
        } catch {
            onError?(error)
        }
    }
}
