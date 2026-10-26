import Foundation
import Observation
import MaxlyDomain

/// Реакции открытого чата: каталог сервера и быстрый ряд меню, поставить и снять реакцию,
/// полный выбор, «Кто отреагировал», анимация только что поставленной реакции (анимодзи и
/// эффекты) и догрузка реакций постов отдельным запросом. Ошибки показывает экран чата
/// (`onError`).
@MainActor
@Observable
public final class ChatReactionsModel {
    public let chatId: String
    /// Каталог реакций сервера. Пуст, пока не загрузился: меню берёт запасной набор.
    public private(set) var catalog: [String] = []
    /// Анимодзи: эмодзи → Lottie (`AnimojiText`).
    public private(set) var animoji: [String: URL] = [:]
    /// Эффекты реакций: эмодзи → Lottie вокруг значка только что поставленной реакции.
    public private(set) var effects: [String: URL] = [:]
    /// Только что поставленная реакция: экран один раз играет её анимацию (`burstShown`).
    public private(set) var burst: ReactionBurst?
    /// Сообщение, для которого открыт полный выбор реакций.
    public var pickerTarget: Message?
    /// Открытый список «Кто отреагировал».
    public var users: ReactionUsersViewModel?
    /// Откуда взять каталог анимодзи (контейнер берёт его у стикеров). Задан — каталог грузится.
    @ObservationIgnored public var loadAnimoji: (@Sendable () async -> AnimojiAssets)? {
        didSet { requestAnimoji() }
    }
    /// Сообщения ленты: своя реакция на сообщении решает, ставится она или снимается.
    @ObservationIgnored public var messages: () -> [Message] = { [] }
    @ObservationIgnored public var onError: ((MaxlyError) -> Void)?
    /// Реакция принята сервером: прежняя ошибка реакции над полем ввода снимается.
    @ObservationIgnored public var onSuccess: (() -> Void)?
    @ObservationIgnored private let repository: any MessageRepository
    @ObservationIgnored private var burstCounter = 0
    @ObservationIgnored private var catalogRequested = false
    /// Посты, чьи реакции уже спрошены отдельным запросом.
    @ObservationIgnored private var asked: Set<String> = []
    /// После ошибки реакции не спрашиваются до этого времени.
    @ObservationIgnored private var retryAt = Date.distantPast

    /// Текст ошибки реакции над полем ввода.
    public static let failure = "Не удалось обновить реакцию"
    /// Сообщений в одном запросе реакций.
    static let batch = 100
    /// Пауза перед повтором реакций после ошибки сервера.
    static let retryAfterError: TimeInterval = 30

    public init(chatId: String, repository: any MessageRepository) {
        self.chatId = chatId
        self.repository = repository
    }

    private func show(_ failure: MaxlyError) {
        onError?(failure)
    }

    /// Реакции ставятся на сообщения, уже принятые сервером.
    public func canReact(_ message: Message) -> Bool {
        message.status == .sent && message.serverId.flatMap { Int64($0) } != nil
    }

    /// Быстрый ряд меню сообщения: начало каталога, своя реакция всегда в нём.
    public func quickReactions(for message: Message) -> [String] {
        ReactionPalette.quick(catalog: catalog, mine: message.content.reactions.mine)
    }

    /// Поставить реакцию или снять свою. Лента меняется сразу, при отказе сервера
    /// возвращается прежнее и показывается ошибка.
    public func toggle(messageId: String, emoji: String) async {
        let mine = messages().first(where: { $0.id == messageId })?.content.reactions.mine
        if mine != emoji {
            // Поставили (не сняли) — значок реакции в плашке играет свою анимацию и эффект вокруг.
            let body = AnimojiText.lookup(catalog: animoji, emoji: emoji)
            let effect = AnimojiText.lookup(catalog: effects, emoji: emoji)
            if body != nil || effect != nil {
                burstCounter += 1
                burst = ReactionBurst(messageId: messageId, emoji: emoji, lottieURL: body, effectURL: effect, id: burstCounter)
            }
        }
        do {
            try await repository.toggleReaction(messageId: messageId, emoji: emoji)
            onSuccess?()
        } catch {
            switch error {
            case .cancelled:
                return
            case .rejected:
                show(error)
            default:
                show(.rejected(Self.failure))
            }
        }
    }

    /// Выбрана реакция в полном списке.
    public func pick(_ emoji: String) async {
        guard let target = pickerTarget else { return }
        pickerTarget = nil
        await toggle(messageId: target.id, emoji: emoji)
    }

    public func showMore(_ message: Message) {
        guard canReact(message) else { return }
        loadCatalog()
        pickerTarget = message
    }

    /// «Кто отреагировал»: есть в группах, если под сообщением есть реакции.
    public func showUsers(_ message: Message) {
        guard canReact(message), !message.content.reactions.isEmpty else { return }
        users = ReactionUsersViewModel(message: message, repository: repository)
    }

    /// Сверить реакции показанных сообщений с сервером: при возврате в приложение пуши
    /// за время в фоне могли потеряться.
    public func refresh() async {
        await repository.refreshReactions(chatId: chatId)
        // После фона реакции постов канала спрашиваются заново.
        asked.removeAll()
    }

    /// Реакции показанных сообщений отдельным запросом (`MSG_GET_REACTIONS`): в истории канала
    /// их нет, а своя реакция с другого устройства видна только в нём. Каждое сообщение
    /// спрашивается один раз за открытие; своё переключение реакции не перезаписывается.
    public func request(for posts: [Message]) {
        guard Date() >= retryAt else { return }
        // Самые новые и не больше одной пачки: остальное спросит следующее обновление ленты.
        let ids = Array(posts.compactMap { post -> String? in
            guard post.status == .sent, let id = post.serverId, Int64(id) != nil, !asked.contains(id) else { return nil }
            return id
        }.suffix(Self.batch))
        guard !ids.isEmpty else { return }
        asked.formUnion(ids)
        let chatId = chatId
        let repository = repository
        Task { [weak self] in
            let ok = await repository.syncReactions(chatId: chatId, messageIds: ids)
            guard let self, !ok else { return }
            self.asked.subtract(ids)
            self.retryAt = Date().addingTimeInterval(Self.retryAfterError)
        }
    }

    /// Экран доиграл анимацию реакции `id`.
    public func burstShown(_ id: Int) {
        if burst?.id == id { burst = nil }
    }

    private func requestAnimoji() {
        guard let loadAnimoji, animoji.isEmpty else { return }
        Task { [weak self] in
            let assets = await loadAnimoji()
            guard let self, !assets.animoji.isEmpty || !assets.effects.isEmpty else { return }
            self.animoji = assets.animoji
            self.effects = assets.effects
        }
    }

    func loadCatalog() {
        guard !catalogRequested else { return }
        catalogRequested = true
        let repository = repository
        Task { [weak self] in
            let catalog = await repository.reactionCatalog()
            guard let self else { return }
            if catalog.isEmpty {
                // Попробовать ещё раз при следующем открытии полного списка.
                self.catalogRequested = false
            } else {
                self.catalog = catalog
            }
        }
    }
}
