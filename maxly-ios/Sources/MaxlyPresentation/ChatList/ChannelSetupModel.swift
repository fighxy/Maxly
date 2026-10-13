import Foundation
import Observation
import MaxlyDomain

/// Настройка только что созданного канала — экраны Max «Приватный канал создан» и «Выберите
/// подписчиков». Канал создаётся приватным; публичный требует Цифровой ID, который оформляется
/// только в официальном мобильном приложении, поэтому здесь — лишь объяснение.
@MainActor
@Observable
public final class ChannelSetupModel {
    public enum Step: Sendable { case type, subscribers }

    /// Почему публичный канал не сделать здесь.
    public enum PublicNotice: String, Identifiable, Sendable {
        case `public`, business
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .public: "Для создания публичного канала нужен Цифровой ID"
            case .business: "Публичный канал для бизнеса"
            }
        }

        public var message: String {
            switch self {
            case .public: "С ним вы сможете создать до 5 публичных каналов. Для создания Цифрового ID перейдите в мобильное приложение MAX."
            case .business: "Для юрлиц, ИП, самозанятых и госорганизаций. Подключается в мобильном приложении MAX."
            }
        }
    }

    public let chatId: String
    public let title: String
    public private(set) var step: Step = .type
    /// Ссылка-приглашение (`https://max.ru/join/…`); `nil` — ещё не пришла.
    public private(set) var link: String?
    public private(set) var people: [Contact] = []
    public private(set) var selected: [String] = []
    public private(set) var busy = false
    public private(set) var done = false
    public var notice: String?
    public var publicNotice: PublicNotice?
    public var query = ""

    @ObservationIgnored private let admin: any ChatAdminRepository
    @ObservationIgnored private let messages: any MessageRepository
    @ObservationIgnored private let contacts: any ContactRepository
    @ObservationIgnored private let currentUserId: String
    @ObservationIgnored private var started = false

    public init(chatId: String, title: String, admin: any ChatAdminRepository, messages: any MessageRepository, contacts: any ContactRepository, currentUserId: String) {
        self.chatId = chatId
        self.title = title
        self.admin = admin
        self.messages = messages
        self.contacts = contacts
        self.currentUserId = currentUserId
    }

    /// Ссылка без схемы, как её пишет Max: `max.ru/join/…`.
    public var shortLink: String? {
        link.map { $0.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") }
    }

    /// Контакты под строкой «Найти по имени».
    public var shown: [Contact] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return people }
        return people.filter { $0.displayName.localizedCaseInsensitiveContains(text) }
    }

    /// Ссылка и контакты. Повторный вызов ничего не делает.
    public func start() async {
        guard !started else { return }
        started = true
        if let snapshot = try? await admin.snapshot(chatId: chatId) { link = snapshot.link }
        for await list in contacts.contacts() {
            people = list
                .filter { $0.id != currentUserId && !$0.isBot && !$0.isServiceAccount }
                .sorted { ContactsViewModel.compare($0.displayName, $1.displayName) }
            break
        }
    }

    public func askPublic(_ kind: PublicNotice = .public) { publicNotice = kind }

    public func linkCopied() { notice = "Ссылка скопирована" }

    /// «Сбросить ссылку»: старая перестаёт работать.
    public func revokeLink() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if let fresh = try await admin.revokeInviteLink(chatId: chatId) { link = fresh }
            notice = "Ссылка обновлена"
        } catch {
            notice = error.userMessage ?? "Не удалось сбросить ссылку"
        }
    }

    /// «Отправить в MAX»: ссылка уходит сообщением в выбранный чат.
    public func sendLink(to targetChatId: String) async {
        guard let link else { return }
        do {
            try await messages.send(text: link, chatId: targetChatId)
            notice = "Ссылка отправлена"
        } catch {
            notice = error.userMessage ?? "Не удалось отправить ссылку"
        }
    }

    /// «Продолжить»: к выбору подписчиков.
    public func next() {
        step = .subscribers
        notice = nil
    }

    public func toggle(_ id: String) {
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) } else { selected.append(id) }
    }

    /// «Добавить»: выбранные становятся подписчиками, канал открывается.
    public func addSubscribers() async {
        guard !selected.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await admin.addMembers(chatId: chatId, userIds: selected)
            done = true
        } catch {
            notice = error.userMessage ?? "Не удалось добавить подписчиков"
        }
    }

    /// «Отменить»: канал открывается без подписчиков.
    public func skip() { done = true }
}
