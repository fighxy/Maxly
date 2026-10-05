import Foundation
import Observation
import OrbitleDomain

/// Экран профиля: собеседник, бот, группа или канал.
///
/// Всё, что экран показывает текстом (подзаголовок, номер, ссылка, счётчики), готовится здесь,
/// чтобы вид оставался тонким и проверялся тестами.
@MainActor
@Observable
public final class ChatProfileViewModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    /// Строка «ключ — значение» в блоке сведений.
    public struct InfoRow: Identifiable, Hashable, Sendable {
        public enum Action: Hashable, Sendable {
            case call(URL)
            case open(URL)
            case copy
        }

        public let id: String
        public let title: String
        public let value: String
        public let action: Action?
        /// Длинный текст (описание) показывается многострочно.
        public let isMultiline: Bool
    }

    public let chatId: String
    public private(set) var state: State = .loading
    public private(set) var profile: ChatProfile?

    @ObservationIgnored private let repository: any ChatProfileRepository
    /// Участники, общие чаты, жалоба и блокировка. `nil` — профиль без этих действий.
    @ObservationIgnored private let actions: (any ProfileActionsRepository)?
    @ObservationIgnored private let formatter: ContactsFormatter
    @ObservationIgnored private let now: () -> Date

    /// `title` и `avatarURL` — то, что уже известно из списка чатов: шапка видна сразу.
    public init(
        chatId: String,
        title: String,
        avatarURL: URL? = nil,
        kind: ChatProfile.Kind? = nil,
        repository: any ChatProfileRepository,
        actions: (any ProfileActionsRepository)? = nil,
        formatter: ContactsFormatter = ContactsFormatter(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.chatId = chatId
        self.repository = repository
        self.actions = actions
        self.formatter = formatter
        self.now = now
        placeholder = ChatProfile(kind: kind ?? .user, chatId: chatId, title: title, avatarURL: avatarURL)
    }

    @ObservationIgnored private let placeholder: ChatProfile

    /// Карточка для шапки: загруженная или то, что известно заранее.
    public var shown: ChatProfile { profile ?? placeholder }

    /// Когда карточка в последний раз пришла с сервера.
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var isFetching = false

    /// Карточка с сервера, если прошлая старше `maxAge` секунд. Шапка чата и профиль
    /// открываются по очереди и не спрашивают сервер дважды подряд: на частые запросы он
    /// отвечает `too.many.requests`.
    ///
    /// Шапка и профиль создаются заново при каждом входе в чат, поэтому свежесть смотрится
    /// и по карточке, недавно пришедшей в репозиторий (`recentProfile`), а не только по своей.
    public func loadIfStale(maxAge: TimeInterval = 60) async {
        if profile != nil, let loadedAt, now().timeIntervalSince(loadedAt) < maxAge { return }
        guard !isFetching else { return }
        if let recent = await repository.recentProfile(chatId: chatId, maxAge: maxAge) {
            profile = recent
            loadedAt = now()
            state = .loaded
            return
        }
        await load()
    }

    public func load() async {
        isFetching = true
        defer { isFetching = false }
        // Сначала карточка с устройства: профиль и статус видны сразу, сервер потом обновит.
        if profile == nil, let cached = await repository.cachedProfile(chatId: chatId) {
            profile = cached
            state = .loaded
        }
        if profile == nil { state = .loading }
        do {
            profile = try await repository.profile(chatId: chatId)
            loadedAt = now()
            state = .loaded
        } catch {
            guard error != .cancelled else { return }
            // Уже показанная карточка остаётся, ошибка видна только без неё.
            if profile == nil { state = .failed(error.userMessage ?? "Не удалось загрузить профиль") }
        }
    }

    // MARK: Шапка

    public var title: String {
        let title = shown.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        switch shown.kind {
        case .saved: return "Избранное"
        case .bot: return "Бот"
        case .channel: return "Канал"
        case .group: return "Группа"
        case .user: return "Пользователь"
        }
    }

    /// Вторая строка шапки: статус человека, «бот», число подписчиков или участников.
    public var subtitle: String {
        let profile = shown
        switch profile.kind {
        case .user:
            return formatter.status(profile.presence, now: now())
        case .bot:
            return "бот"
        case .saved:
            return "ваши сообщения и заметки"
        case .channel:
            guard let count = profile.participants else { return profile.isPublic ? "публичный канал" : "канал" }
            return "\(Self.grouped(count)) \(Self.plural(count, "подписчик", "подписчика", "подписчиков"))"
        case .group:
            guard let count = profile.participants else { return "группа" }
            return "\(Self.grouped(count)) \(Self.plural(count, "участник", "участника", "участников"))"
        }
    }

    public var isOnline: Bool { shown.presence == .online }
    public var isOfficial: Bool { shown.isOfficial }

    /// Кнопка «Написать» нужна там, где профиль открыт не из самого чата (например, из контактов).
    public var canWrite: Bool {
        switch shown.kind {
        case .user, .bot, .saved: true
        case .group, .channel: false
        }
    }

    // MARK: Сведения

    public var infoRows: [InfoRow] {
        guard let profile else { return [] }
        var rows: [InfoRow] = []
        if let phone = profile.phone, profile.kind == .user {
            let digits = phone.filter(\.isNumber)
            rows.append(InfoRow(
                id: "phone",
                title: "телефон",
                value: PhoneNumber.display(phone),
                action: URL(string: "tel:+" + digits).map(InfoRow.Action.call),
                isMultiline: false
            ))
        }
        if let description = profile.description {
            let title: String
            switch profile.kind {
            case .user, .saved: title = "о себе"
            case .bot, .channel, .group: title = "описание"
            }
            rows.append(InfoRow(id: "description", title: title, value: description, action: .copy, isMultiline: true))
        }
        if let url = profile.linkURL {
            rows.append(InfoRow(
                id: "link",
                title: profile.kind == .channel || profile.kind == .group ? "ссылка" : "имя пользователя",
                value: Self.shortLink(url),
                action: .open(url),
                isMultiline: false
            ))
        }
        return rows
    }

    /// Команда бота для списка: `/start` и пояснение.
    public struct CommandRow: Identifiable, Hashable, Sendable {
        public var id: String { command }
        public let command: String
        public let description: String?
    }

    public var commands: [CommandRow] {
        (profile?.commands ?? []).map { CommandRow(command: "/" + $0.name, description: $0.description) }
    }

    // MARK: Общие медиа

    /// Вложения чата по вкладкам: окно чата, история из кэша и всё, что отдал сервер.
    public private(set) var shared = SharedMedia()
    /// Открытая вкладка; пустые вкладки не показываются.
    public var sharedTab: SharedMediaTab = .media
    /// Идёт обход общих медиа на сервере.
    public private(set) var isLoadingRemoteShared = false

    /// История из кэша устройства: общие медиа не ограничены окном, загруженным в чате.
    @ObservationIgnored private var history: [Message] = []
    @ObservationIgnored private var historyLoaded = false
    @ObservationIgnored private var window: [Message] = []
    @ObservationIgnored private var sharedUserId = ""
    /// Общие медиа с сервера (`CHAT_MEDIA`): не зависят от того, докуда пролистан чат.
    @ObservationIgnored private var pager = SharedMediaPager()

    /// `window` — сообщения открытого чата (свежее кэша), `history` — сохранённая история,
    /// читается один раз.
    public func updateShared(
        _ window: [Message],
        currentUserId: String,
        history load: () async -> [Message] = { [] }
    ) async {
        if !historyLoaded {
            historyLoaded = true
            history = await load()
        }
        self.window = window
        sharedUserId = currentUserId
        rebuildShared()
    }

    /// Все общие медиа чата с сервера, страница за страницей, пока сервер присылает новое.
    /// `window` — окно чата: его последнее серверное сообщение служит якорем первой страницы.
    /// Отмена задачи (профиль закрыт) сохраняет место: следующий вызов продолжит с него.
    ///
    /// Между страницами `pause`: обход идёт в фоне, а на очередь запросов без паузы сервер
    /// отвечает `too.many.requests` и заодно перестаёт отдавать историю открытого чата.
    /// Первая же неудачная страница останавливает весь обход, а не только свою вкладку:
    /// остальные вкладки получили бы тот же отказ. Следующее открытие профиля продолжит.
    public func loadRemoteShared(
        window: [Message],
        pause: Duration = .seconds(1),
        fetch: (SharedMediaRequest) async -> [Message]?
    ) async {
        guard !isLoadingRemoteShared, let latest = SharedMediaPager.anchor(in: window) else { return }
        isLoadingRemoteShared = true
        defer { isLoadingRemoteShared = false }
        pager.retryFailed()
        var first = true
        var failed = false
        while !Task.isCancelled, !failed {
            let round = pager.round(latest: latest)
            if round.isEmpty { break }
            var changed = false
            for request in round {
                if !first {
                    try? await Task.sleep(for: pause)
                    if Task.isCancelled { break }
                }
                first = false
                let page = await fetch(request)
                // Ответ отменённой задачи не значит, что у вкладки всё: её продолжит следующий вызов.
                if Task.isCancelled { break }
                if pager.receive(page, for: request) { changed = true }
                if page == nil {
                    failed = true
                    break
                }
            }
            if changed { rebuildShared() }
        }
    }

    /// Окно новее кэша, кэш новее сервера: локальная копия знает скачанные файлы.
    private func rebuildShared() {
        let windowIds = Set(window.map(\.id))
        let older = history.filter { !windowIds.contains($0.id) && $0.timestamp <= (window.first?.timestamp ?? .distantFuture) }
        let local = older + window
        let localKeys = Set(local.map(SharedMediaPager.key))
        let remote = pager.messages.values.filter { !localKeys.contains($0.id) }
        let all = remote.isEmpty ? local : (local + remote).sorted { $0.timestamp < $1.timestamp }
        let next = SharedMedia.collect(all, currentUserId: sharedUserId, now: now())
        guard next != shared else { return }
        shared = next
        if let first = next.tabs.first, !next.tabs.contains(sharedTab) { sharedTab = first }
    }

    /// Вторая строка шапки чата с живыми данными списка (сеть, «печатает…»).
    public func headerStatus(_ live: ChatHeaderLive) -> ChatHeaderStatus {
        ChatHeaderStatus.make(kind: shown.kind, subtitle: subtitle, isOnline: isOnline, live: live)
    }

    /// Что отдать в «Поделиться»: публичная ссылка, если есть.
    public var shareURL: URL? { profile?.linkURL }

    // MARK: Форматирование

    /// `https://max.ru/helper_bot` → `max.ru/helper_bot`.
    static func shortLink(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        return text
    }

    /// `12500` → `12 500` (узкий неразрывный пробел).
    static func grouped(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    /// Русское множественное число: 1 подписчик, 2 подписчика, 5 подписчиков, 11 подписчиков.
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tens = count % 100
        let units = count % 10
        if (11...14).contains(tens) { return many }
        switch units {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    // MARK: Участники, общие чаты, жалоба, блокировка

    /// Участники группы (первая страница сервера). Пусто, пока не загружены или это не группа.
    public private(set) var members: [ProfileMember] = []
    /// Общие чаты с собеседником.
    public private(set) var commonChats: [CommonChat] = []
    /// В чёрном списке ли собеседник. `nil` — неизвестно (ещё не спросили или это не человек).
    public private(set) var isBlocked: Bool?
    /// Причины жалобы: лист открывается, когда они пришли.
    public private(set) var complaintReasons: [ComplaintReason] = []
    /// Идёт блокировка или отправка жалобы: кнопки не нажимаются.
    public private(set) var isActing = false
    /// Короткое уведомление: «Жалоба отправлена», «Заблокирован», ошибка.
    public private(set) var actionNotice: String?
    @ObservationIgnored private var extrasLoaded = false

    /// Собеседник-человек: его можно заблокировать и на него можно пожаловаться.
    private var personId: String? {
        guard shown.kind == .user || shown.kind == .bot else { return nil }
        return shown.peerId
    }

    /// На кого жалоба из этого профиля: человек или канал. У групп и ботов — нет.
    public var complaintTarget: ComplaintTarget? {
        switch shown.kind {
        case .user: shown.peerId.map(ComplaintTarget.user)
        case .channel: .channel(chatId)
        case .group, .bot, .saved: nil
        }
    }

    public var canBlock: Bool { actions != nil && personId != nil }

    /// «12 участников», «1 200 подписчиков» — подпись общего чата.
    public static func membersText(_ count: Int, channel: Bool) -> String {
        channel
            ? "\(grouped(count)) \(plural(count, "подписчик", "подписчика", "подписчиков"))"
            : "\(grouped(count)) \(plural(count, "участник", "участника", "участников"))"
    }

    /// Участники группы, общие чаты с человеком и его место в чёрном списке. Один раз на профиль,
    /// после того как пришла карточка (без неё неизвестны вид и собеседник).
    public func loadExtras() async {
        guard let actions, !extrasLoaded, profile != nil else { return }
        extrasLoaded = true
        switch shown.kind {
        case .group:
            if let rows = try? await actions.members(chatId: chatId) { members = rows }
        case .user, .bot:
            guard let person = personId else { return }
            if shown.kind == .user, let chats = try? await actions.commonChats(userId: person) { commonChats = chats }
            if let blocked = try? await actions.isBlocked(userId: person) { isBlocked = blocked }
        case .channel, .saved:
            break
        }
    }

    /// Заблокировать или разблокировать собеседника.
    public func toggleBlocked() async {
        guard let actions, let person = personId, !isActing else { return }
        let block = isBlocked != true
        isActing = true
        defer { isActing = false }
        do {
            try await actions.setBlocked(userId: person, blocked: block)
            isBlocked = block
            announce(block ? "Пользователь заблокирован" : "Пользователь разблокирован")
        } catch {
            announce(error.userMessage ?? (block ? "Не удалось заблокировать" : "Не удалось разблокировать"))
        }
    }

    /// Причины жалобы с сервера. `false` — их нет или сервер отказал (уведомление показано).
    public func loadComplaintReasons() async -> Bool {
        guard let actions, let target = complaintTarget, !isActing else { return false }
        isActing = true
        defer { isActing = false }
        do {
            complaintReasons = try await actions.complaintReasons(for: target)
            if complaintReasons.isEmpty { announce("Сервер не прислал причины жалобы") }
            return !complaintReasons.isEmpty
        } catch {
            announce(error.userMessage ?? "Не удалось загрузить причины жалобы")
            return false
        }
    }

    public func complain(reasonId: Int) async {
        guard let actions, let target = complaintTarget, !isActing else { return }
        isActing = true
        defer { isActing = false }
        do {
            let accepted = try await actions.complain(about: target, reasonId: reasonId)
            announce(accepted ? "Жалоба отправлена" : "Сервер не принял жалобу")
        } catch {
            announce(error.userMessage ?? "Не удалось отправить жалобу")
        }
    }

    private func announce(_ text: String) {
        actionNotice = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.actionNotice == text else { return }
            self.actionNotice = nil
        }
    }
}
