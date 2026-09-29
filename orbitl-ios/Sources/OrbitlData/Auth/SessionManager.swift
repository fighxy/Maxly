import Foundation
import OrbitlDomain

/// Сессия приложения: шаги входа через ядро, кэш в базе, очистка только при явном выходе.
///
/// Токен и device id лежат в Keychain ядра (`com.max.kmp.default`). Здесь их нет.
public actor SessionManager: AuthService {
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
    private var phone = ""
    private var codeToken: String?
    private var trackId: String?
    private var registerToken: String?
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

    public nonisolated func phases() -> AsyncStream<AuthPhase> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.remove(id) }
            }
        }
    }

    public var isAuthorized: Bool {
        if case .signedIn = phase { true } else { false }
    }

    public func restoreSession() async {
        publish(.restoring)
        watchCore()
        let stored = await core.hasStoredToken()
        let remembered = defaults.string(forKey: Self.userDefaultsKey) ?? ""
        do {
            switch try await core.start() {
            case .ready:
                let id = await core.currentUserId()
                await enter(userId: id.isEmpty ? remembered : id)
            case .connecting, .reconnecting, .idle, .failed:
                if stored {
                    await showCache(userId: remembered)
                } else {
                    publish(.signedOut)
                }
            case .tokenRejected:
                publish(.expired)
            case .awaitingAuth:
                publish(.signedOut)
            }
        } catch {
            if stored {
                await showCache(userId: remembered)
            } else {
                publish(.signedOut)
            }
        }
    }

    public func requestCode(phone: String) async throws(OrbitlError) {
        do {
            let code = try await core.requestCode(phone: phone, resend: false)
            self.phone = phone
            codeToken = code.token
            publish(.codeSent(codeLength: code.codeLength))
        } catch {
            throw CoreErrors.orbitl(error)
        }
    }

    public func resendCode() async throws(OrbitlError) {
        guard !phone.isEmpty else { throw .invalidRequest }
        do {
            let code = try await core.requestCode(phone: phone, resend: true)
            codeToken = code.token
            publish(.codeSent(codeLength: code.codeLength))
        } catch {
            throw CoreErrors.orbitl(error)
        }
    }

    public func verifyCode(_ code: String) async throws(OrbitlError) {
        guard let codeToken else { throw .invalidRequest }
        do {
            try await apply(await core.verifyCode(token: codeToken, code: code))
        } catch let error as OrbitlError {
            throw error
        } catch {
            throw CoreErrors.orbitl(error)
        }
    }

    public func submitPassword(_ password: String) async throws(OrbitlError) {
        guard let trackId else { throw .invalidRequest }
        do {
            try await apply(await core.checkPassword(trackId: trackId, password: password))
        } catch let error as OrbitlError {
            throw error
        } catch {
            throw CoreErrors.orbitl(error)
        }
    }

    public func register(firstName: String, lastName: String) async throws(OrbitlError) {
        guard let registerToken else { throw .invalidRequest }
        do {
            let step = try await core.register(token: registerToken, firstName: firstName, lastName: lastName)
            try await apply(step)
        } catch let error as OrbitlError {
            throw error
        } catch {
            throw CoreErrors.orbitl(error)
        }
    }

    public func logout() async {
        await sync.stopEvents()
        await sync.networkLost()
        try? await core.logout()
        await eraseLocal()
        defaults.removeObject(forKey: Self.userDefaultsKey)
        await messages.setCurrentUser(id: "")
        codeToken = nil
        trackId = nil
        registerToken = nil
        phone = ""
        publish(.signedOut)
    }

    private func apply(_ step: CoreAuthStep) async throws(OrbitlError) {
        switch step {
        case .loggedIn(let userId):
            await enter(userId: userId)
        case .password(let track, let hint):
            trackId = track
            publish(.password(hint: hint))
        case .register(let token):
            registerToken = token
            publish(.registration)
        }
    }

    /// Вход. Чужой user id стирает кэш предыдущего аккаунта до загрузки его чатов.
    private func enter(userId: String) async {
        let previous = defaults.string(forKey: Self.userDefaultsKey)
        if let previous, !userId.isEmpty, previous != userId {
            await sync.stopEvents()
            await sync.networkLost()
            await eraseLocal()
        }
        if !userId.isEmpty {
            defaults.set(userId, forKey: Self.userDefaultsKey)
        }
        await messages.setCurrentUser(id: userId)
        await sync.startEvents(core)
        publish(.signedIn(userId: userId))
        await sync.networkBecameAvailable()
        try? await chats.refresh()
    }

    /// Чаты и сообщения стираются в своих контекстах, иначе ModelActor оставит старые объекты.
    private func eraseLocal() async {
        try? await messages.removeAll()
        try? await chats.removeAll()
        try? stack.eraseUsersAndMedia()
        await media.clearCache()
    }

    /// Токен есть, сокет ещё не онлайн: показываем кэш и не трогаем базу.
    private func showCache(userId: String) async {
        await messages.setCurrentUser(id: userId)
        await sync.startEvents(core)
        publish(.signedIn(userId: userId))
    }

    private func watchCore() {
        guard coreWatch == nil else { return }
        coreWatch = Task { [weak self] in
            guard let self else { return }
            let phases = await self.corePhases()
            for await next in phases {
                await self.observe(next)
            }
        }
    }

    private func corePhases() -> AsyncStream<CorePhase> {
        core.phases()
    }

    private func observe(_ next: CorePhase) async {
        switch next {
        case .tokenRejected:
            await sync.networkLost()
            publish(.expired)
        case .ready:
            guard isAuthorized else { return }
            await sync.networkBecameAvailable()
        case .reconnecting, .connecting, .failed:
            guard isAuthorized else { return }
            await sync.networkLost()
        case .idle, .awaitingAuth:
            break
        }
    }

    private func add(_ id: UUID, _ continuation: AsyncStream<AuthPhase>.Continuation) {
        continuations[id] = continuation
        continuation.yield(phase)
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }

    private func publish(_ phase: AuthPhase) {
        self.phase = phase
        for continuation in continuations.values {
            continuation.yield(phase)
        }
    }
}
