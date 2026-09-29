import Foundation
import OrbitlDomain

/// `UserDefaults` потокобезопасен. Сессия и тесты держат один и тот же suite.
extension UserDefaults: @retroactive @unchecked Sendable {}

/// Сессия приложения: шаги входа через ядро, кэш в базе, очистка только при явном выходе.
///
/// Токен и device id лежат в Keychain ядра (`com.max.kmp.default`). Здесь их нет.
///
/// Попытка входа нумеруется (`attempt`). `cancelLogin` и `logout` начинают новую попытку,
/// поэтому поздний ответ ядра на код или пароль из старой попытки не меняет шаг, а метод
/// бросает `OrbitlError.cancelled`. Исключение — успешный вход: ядро к этому моменту уже
/// сохранило токен, и приложение входит, чтобы не расходиться с ядром.
public actor SessionManager: AuthService, ConnectionStatusProvider {
    static let userDefaultsKey = "orbitl.lastUserId"

    private let core: any MaxCore
    private let stack: SwiftDataStack
    private let chats: ChatRepositoryImpl
    private let messages: MessageRepositoryImpl
    private let sync: SyncEngine
    private let media: any MediaRepository
    private let defaults: UserDefaults

    private var phase: AuthPhase = .restoring
    private var continuations: [UUID: AsyncStream<AuthPhase>.Continuation] = [:]
    private var connection: ConnectionState = .connecting
    private var connectionContinuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private var phone = ""
    private var codeToken: String?
    private var trackId: String?
    private var registerToken: String?
    private var attempt = 0
    private var isLoggingOut = false
    /// Растёт в начале каждого выхода. Вход, начатый до выхода, после него не продолжается:
    /// между шагами входа актор отпускается, и выход может пройти целиком.
    private var logouts = 0
    private var coreWatch: Task<Void, Never>?

    public init(
        core: any MaxCore,
        stack: SwiftDataStack,
        chats: ChatRepositoryImpl,
        messages: MessageRepositoryImpl,
        sync: SyncEngine,
        media: any MediaRepository,
        defaults: UserDefaults = .standard
    ) {
        self.core = core
        self.stack = stack
        self.chats = chats
        self.messages = messages
        self.sync = sync
        self.media = media
        self.defaults = defaults
    }

    // MARK: Потоки

    public nonisolated func phases() -> AsyncStream<AuthPhase> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.remove(id) }
            }
        }
    }

    public nonisolated func connectionStates() -> AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addConnection(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeConnection(id) }
            }
        }
    }

    public var isAuthorized: Bool {
        if case .signedIn = phase { true } else { false }
    }

    /// Текущий шаг. Для тестов и отладки.
    public var currentPhase: AuthPhase { phase }

    // MARK: Восстановление

    public func restoreSession() async {
        let epoch = logouts
        publish(.restoring)
        watchCore()
        let stored = await core.hasStoredToken()
        let remembered = rememberedUserId
        Log.info(.auth, "Восстановление сессии: токен \(stored ? "есть" : "нет")")
        let started: CorePhase?
        do {
            started = try await core.start()
        } catch {
            started = nil
        }
        Log.info(.auth, "Старт ядра: \(started?.rawValue ?? "ошибка")")
        // Пока ядро подключалось, фазу мог сменить поток ядра (отказ токена) или выход.
        guard phase == .restoring else { return }
        switch started {
        case .ready:
            setConnection(.online)
            let id = await core.currentUserId()
            await enter(userId: id.isEmpty ? remembered : id, epoch: epoch)
        case .tokenRejected:
            await expire()
        case .awaitingAuth:
            setConnection(.online)
            publish(.signedOut)
        case .connecting, .reconnecting, .idle, .failed, nil:
            if started == nil || started == .failed || started == .idle {
                setConnection(.offline)
            }
            if stored {
                await showCache(userId: remembered, epoch: epoch)
            } else {
                publish(.signedOut)
            }
        }
    }

    // MARK: Шаги входа

    public func requestCode(phone raw: String) async throws(OrbitlError) {
        let phone = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty else { throw .rejected("Введите номер телефона") }
        guard !isAuthorized else { throw .invalidRequest }
        let generation = attempt
        Log.info(.auth, "Запрос кода на \(Log.mask(phone: phone))")
        let code: CoreCode
        do {
            code = try await core.requestCode(phone: phone, resend: false)
        } catch {
            Log.warning(.auth, "Код не отправлен")
            throw AuthErrors.map(error, during: .requestCode)
        }
        try ensureCurrent(generation)
        Log.info(.auth, "Код отправлен, длина \(code.codeLength.map { String($0) } ?? "не указана")")
        self.phone = phone
        codeToken = code.token
        trackId = nil
        registerToken = nil
        publish(.codeSent(codeLength: code.codeLength))
    }

    public func resendCode() async throws(OrbitlError) {
        guard !phone.isEmpty, codeToken != nil else { throw .invalidRequest }
        let generation = attempt
        Log.info(.auth, "Повторная отправка кода")
        let code: CoreCode
        do {
            code = try await core.requestCode(phone: phone, resend: true)
        } catch {
            throw AuthErrors.map(error, during: .requestCode)
        }
        try ensureCurrent(generation)
        codeToken = code.token
        publish(.codeSent(codeLength: code.codeLength))
    }

    public func verifyCode(_ raw: String) async throws(OrbitlError) {
        let code = raw.filter { !$0.isWhitespace }
        guard !code.isEmpty else { throw .rejected("Введите код из SMS") }
        guard let codeToken else { throw .invalidRequest }
        let generation = attempt
        let epoch = logouts
        let step: CoreAuthStep
        Log.info(.auth, "Проверка кода")
        do {
            step = try await core.verifyCode(token: codeToken, code: code)
        } catch {
            Log.warning(.auth, "Код не принят")
            if AuthErrors.isExpiredCode(error), await renewCode(generation: generation) {
                throw .codeRenewed
            }
            throw AuthErrors.map(error, during: .verifyCode)
        }
        try await apply(step, generation: generation, epoch: epoch)
    }

    /// Устаревший код заменяется новым на тот же номер, чтобы не гонять человека назад
    /// к вводу номера. `false`, если новый код получить не удалось.
    private func renewCode(generation: Int) async -> Bool {
        guard !phone.isEmpty, generation == attempt else { return false }
        guard let code = try? await core.requestCode(phone: phone, resend: false) else { return false }
        guard generation == attempt, !isLoggingOut else { return false }
        codeToken = code.token
        publish(.codeSent(codeLength: code.codeLength))
        return true
    }

    public func submitPassword(_ password: String) async throws(OrbitlError) {
        guard !password.isEmpty else { throw .rejected("Введите пароль") }
        guard let trackId else { throw .invalidRequest }
        let generation = attempt
        let epoch = logouts
        let step: CoreAuthStep
        Log.info(.auth, "Проверка облачного пароля")
        do {
            step = try await core.checkPassword(trackId: trackId, password: password)
        } catch {
            Log.warning(.auth, "Облачный пароль не принят")
            throw AuthErrors.map(error, during: .password)
        }
        try await apply(step, generation: generation, epoch: epoch)
    }

    public func register(firstName rawFirst: String, lastName rawLast: String) async throws(OrbitlError) {
        let firstName = rawFirst.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = rawLast.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstName.isEmpty else { throw .rejected("Введите имя") }
        guard let registerToken else { throw .invalidRequest }
        let generation = attempt
        let epoch = logouts
        let step: CoreAuthStep
        do {
            step = try await core.register(token: registerToken, firstName: firstName, lastName: lastName)
        } catch {
            throw AuthErrors.map(error, during: .register)
        }
        try await apply(step, generation: generation, epoch: epoch)
    }

    public func cancelLogin() async {
        guard !isAuthorized else { return }
        attempt += 1
        forgetLoginAttempt()
        publish(.signedOut)
    }

    public func logout() async {
        Log.info(.auth, "Выход из аккаунта")
        attempt += 1
        logouts += 1
        isLoggingOut = true
        defer { isLoggingOut = false }
        await sync.stopEvents()
        await sync.networkLost()
        await sync.reset()
        try? await core.logout()
        await eraseLocal()
        defaults.removeObject(forKey: Self.userDefaultsKey)
        await messages.setCurrentUser(id: "")
        forgetLoginAttempt()
        publish(.signedOut)
    }

    // MARK: Внутреннее

    private var rememberedUserId: String {
        defaults.string(forKey: Self.userDefaultsKey) ?? ""
    }

    private var signedInUserId: String? {
        if case .signedIn(let id) = phase { id } else { nil }
    }

    /// Ответ относится к текущей попытке, и вызывающую задачу не отменили.
    private func ensureCurrent(_ generation: Int) throws(OrbitlError) {
        if generation != attempt || isLoggingOut || Task.isCancelled {
            throw .cancelled
        }
    }

    private func forgetLoginAttempt() {
        codeToken = nil
        trackId = nil
        registerToken = nil
        phone = ""
    }

    private func apply(_ step: CoreAuthStep, generation: Int, epoch: Int) async throws(OrbitlError) {
        switch step {
        case .loggedIn: Log.info(.auth, "Шаг входа: вход выполнен")
        case .password: Log.info(.auth, "Шаг входа: нужен облачный пароль")
        case .register: Log.info(.auth, "Шаг входа: регистрация")
        }
        switch step {
        case .loggedIn(let userId):
            // Токен уже в Keychain ядра. Отменённая попытка всё равно входит, иначе
            // приложение показало бы вход при живой сессии ядра. Выход важнее.
            guard !isLoggingOut, epoch == logouts else { throw .cancelled }
            let id = userId.isEmpty ? await core.currentUserId() : userId
            await enter(userId: id, epoch: epoch)
        case .password(let track, let hint):
            try ensureCurrent(generation)
            trackId = track
            publish(.password(hint: hint))
        case .register(let token):
            try ensureCurrent(generation)
            registerToken = token
            publish(.registration)
        }
    }

    /// Вход. Чужой user id стирает кэш предыдущего аккаунта до загрузки его чатов.
    ///
    /// `epoch` — число выходов на момент начала операции. Если между шагами прошёл выход,
    /// вход обрывается: иначе он снова включил бы пуши и опрос и показал бы список чатов
    /// уже после экрана входа.
    private func enter(userId: String, epoch: Int) async {
        guard epoch == logouts else { return }
        let previous = defaults.string(forKey: Self.userDefaultsKey)
        let id = userId.isEmpty ? (previous ?? "") : userId
        Log.info(.auth, "Вход: пользователь \(id.isEmpty ? "?" : id)")
        if let previous, !id.isEmpty, previous != id {
            Log.info(.auth, "Другой аккаунт: локальный кэш прежнего стирается")
            await sync.stopEvents()
            await sync.networkLost()
            await sync.reset()
            await eraseLocal()
            guard epoch == logouts else { return }
        }
        if !id.isEmpty {
            defaults.set(id, forKey: Self.userDefaultsKey)
        }
        forgetLoginAttempt()
        await messages.setCurrentUser(id: id)
        guard epoch == logouts else { return }
        await sync.startEvents(core)
        guard epoch == logouts else { return }
        publish(.signedIn(userId: id))
        await sync.networkBecameAvailable()
        guard epoch == logouts else { return }
        try? await chats.refresh()
    }

    /// Токен ядра отклонён. База остаётся, пока пользователь сам не выйдет.
    private func expire() async {
        Log.warning(.auth, "Сервер отклонил сохранённый токен")
        await sync.networkLost()
        forgetLoginAttempt()
        publish(.expired)
    }

    /// Чаты и сообщения стираются в своих контекстах, иначе ModelActor оставит старые объекты.
    private func eraseLocal() async {
        try? await messages.removeAll()
        try? await chats.removeAll()
        try? stack.eraseUsersAndMedia()
        await media.clearCache()
    }

    /// Токен есть, сокет ещё не онлайн: показываем кэш и не трогаем базу.
    private func showCache(userId: String, epoch: Int) async {
        await messages.setCurrentUser(id: userId)
        guard epoch == logouts else { return }
        await sync.startEvents(core)
        guard epoch == logouts else { return }
        publish(.signedIn(userId: userId))
    }

    private func watchCore() {
        guard coreWatch == nil else { return }
        // Сильная ссылка берётся только на время одной фазы: поток ядра бесконечен,
        // и сессия не должна жить из-за него вечно.
        coreWatch = Task { [weak self] in
            guard let phases = await self?.corePhases() else { return }
            for await next in phases {
                guard let self else { return }
                await self.observe(next)
            }
        }
    }

    private func corePhases() -> AsyncStream<CorePhase> {
        core.phases()
    }

    /// Фаза ядра после старта: сеть для синхронизации, индикатор соединения и отказ токена.
    func observe(_ next: CorePhase) async {
        Log.debug(.core, "Фаза ядра: \(next.rawValue)")
        switch next {
        case .tokenRejected:
            setConnection(.offline)
            // Во время входа по коду старый отказ токена шаг не сбрасывает.
            guard isAuthorized || phase == .restoring else { return }
            await expire()
        case .ready:
            setConnection(.online)
            guard let current = signedInUserId else { return }
            let epoch = logouts
            let id = await core.currentUserId()
            guard signedInUserId == current else { return }
            if !id.isEmpty, id != current {
                // Кэш показывался под запомненным id, а ядро вошло другим аккаунтом.
                await enter(userId: id, epoch: epoch)
            } else {
                await sync.networkBecameAvailable()
            }
        case .connecting, .reconnecting:
            setConnection(.connecting)
            if isAuthorized { await sync.networkLost() }
        case .failed, .idle:
            setConnection(.offline)
            if isAuthorized { await sync.networkLost() }
        case .awaitingAuth:
            setConnection(.online)
        }
    }

    /// Подписчик мог уйти раньше, чем эта задача добралась до актора: тогда его снятие
    /// уже отработало, и сохранять его нельзя, иначе он останется в словаре навсегда.
    private func add(_ id: UUID, _ continuation: AsyncStream<AuthPhase>.Continuation) {
        if case .terminated = continuation.yield(phase) { return }
        continuations[id] = continuation
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }

    private func addConnection(_ id: UUID, _ continuation: AsyncStream<ConnectionState>.Continuation) {
        if case .terminated = continuation.yield(connection) { return }
        connectionContinuations[id] = continuation
    }

    private func removeConnection(_ id: UUID) {
        connectionContinuations[id] = nil
    }

    private func publish(_ phase: AuthPhase) {
        self.phase = phase
        for continuation in continuations.values {
            continuation.yield(phase)
        }
    }

    private func setConnection(_ state: ConnectionState) {
        guard state != connection else { return }
        connection = state
        for continuation in connectionContinuations.values {
            continuation.yield(state)
        }
    }
}
