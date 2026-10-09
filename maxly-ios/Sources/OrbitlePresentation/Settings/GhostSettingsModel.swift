import Foundation
import Observation
import OrbitleDomain

/// Блок «Дополнительно» в «Безопасности» и строка своего статуса в шапке настроек
/// (docs/privacy.md).
///
/// Свой статус спрашивается каждые `interval` (15 с), пока шапка на экране, приложение не в фоне
/// и включено «Показывать мой онлайн». Сразу — при появлении шапки, при возврате приложения
/// из фона и при переключении режима призрака.
@MainActor
@Observable
public final class GhostSettingsModel {
    public static let defaultInterval: Duration = .seconds(15)

    public private(set) var ghostMode: Bool
    public private(set) var hideReadReceipts: Bool
    public private(set) var showsOwnPresence: Bool
    /// Последний ответ сервера о себе. `nil` — ещё не спрашивали или строка выключена.
    public private(set) var ownPresence: Contact.Presence?

    public private(set) var isScreenVisible = false
    public private(set) var isAppForeground: Bool
    /// Сколько раз спросили свой статус. Для тестов и журнала.
    public private(set) var checks = 0

    @ObservationIgnored private let controls: any GhostControls
    @ObservationIgnored private let store: any SelfCheckStore
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let formatter: ContactsFormatter
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    /// Номер последнего начатого запроса и последнего применённого: поздний ответ старого
    /// запроса не перетирает свежий.
    @ObservationIgnored private var startedCheck = 0
    @ObservationIgnored private var appliedCheck = 0

    public init(
        controls: any GhostControls,
        store: any SelfCheckStore,
        isAppForeground: Bool = true,
        interval: Duration = GhostSettingsModel.defaultInterval,
        formatter: ContactsFormatter = ContactsFormatter(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.controls = controls
        self.store = store
        self.isAppForeground = isAppForeground
        self.interval = interval
        self.formatter = formatter
        self.sleep = sleep
        ghostMode = controls.ghostMode()
        hideReadReceipts = controls.hideReadReceipts()
        showsOwnPresence = store.showsOwnPresence()
    }

    /// Подписка на изменения флагов в ядре (в том числе с другого экрана).
    public func activate() {
        guard watch == nil else { return }
        let stream = controls.ghostChanges()
        watch = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                self.ghostMode = state.ghostMode
                self.hideReadReceipts = state.hideReadReceipts
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
        stopPolling()
    }

    // MARK: Переключатели

    public func setGhostMode(_ enabled: Bool) async {
        guard enabled != ghostMode else { return }
        ghostMode = enabled
        await controls.setGhostMode(enabled)
        // Сразу видно, что сервер думает о нас теперь.
        checkSoon()
    }

    public func setHideReadReceipts(_ hidden: Bool) async {
        guard hidden != hideReadReceipts else { return }
        hideReadReceipts = hidden
        await controls.setHideReadReceipts(hidden)
    }

    public func setShowsOwnPresence(_ shows: Bool) {
        guard shows != showsOwnPresence else { return }
        showsOwnPresence = shows
        store.setShowsOwnPresence(shows)
        if shows {
            restartPolling()
        } else {
            stopPolling()
            ownPresence = nil
        }
    }

    // MARK: Видимость

    /// Шапка настроек появилась или ушла с экрана.
    public func setScreenVisible(_ visible: Bool) {
        guard visible != isScreenVisible else { return }
        isScreenVisible = visible
        if visible { restartPolling() } else { stopPolling() }
    }

    /// Приложение вернулось из фона или ушло в фон.
    public func setAppForeground(_ foreground: Bool) {
        guard foreground != isAppForeground else { return }
        isAppForeground = foreground
        if foreground { restartPolling() } else { stopPolling() }
    }

    /// Опрос идёт прямо сейчас.
    public var isPolling: Bool { poll != nil }

    private var shouldPoll: Bool {
        showsOwnPresence && isScreenVisible && isAppForeground
    }

    // MARK: Строка в шапке

    /// «в сети» или «был(а) …» со строчной, как в шапке чата (`test-fixtures/presence`).
    /// `nil` — строка выключена или статус неизвестен.
    public func ownPresenceText(now: Date) -> String? {
        guard showsOwnPresence, let ownPresence else { return nil }
        let text = formatter.status(ownPresence, now: now)
        return ChatHeaderStatus.make(kind: .user, subtitle: text, isOnline: ownPresence == .online, live: ChatHeaderLive()).text
    }

    public var isOwnPresenceOnline: Bool { ownPresence == .online }

    // MARK: Опрос

    /// Переключили режим: опрос с начала, если он идёт; иначе один запрос, если приложение на
    /// экране и строка включена (шапка увидит свежий ответ, когда вернётся на экран).
    private func checkSoon() {
        if shouldPoll {
            restartPolling()
        } else if showsOwnPresence, isAppForeground {
            Task { await self.checkNow() }
        }
    }

    private func restartPolling() {
        stopPolling()
        guard shouldPoll else { return }
        let sleep = sleep
        let interval = interval
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkNow()
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
            }
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    /// Один запрос своего статуса.
    public func checkNow() async {
        startedCheck += 1
        let number = startedCheck
        checks += 1
        do {
            let presence = try await controls.checkOwnPresence()
            guard number > appliedCheck, showsOwnPresence else { return }
            appliedCheck = number
            ownPresence = presence
        } catch {
            // Строка остаётся с прошлым ответом, следующий запрос — по расписанию.
            Log.debug(.settings, "Свой статус не получен: \(error)")
        }
    }
}
