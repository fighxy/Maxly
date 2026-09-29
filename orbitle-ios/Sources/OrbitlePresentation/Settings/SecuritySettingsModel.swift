import Foundation
import Observation
import OrbitleDomain

/// Состояние загрузки раздела экрана.
public enum Loadable<Value: Sendable & Equatable>: Sendable, Equatable {
    case loading
    case loaded(Value)
    case failed(String)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// «Безопасность»: пароль для входа, почта восстановления и чёрный список.
@MainActor
@Observable
public final class SecuritySettingsModel {
    public private(set) var twoFactor: Loadable<TwoFactorStatus> = .loading
    public private(set) var blocked: Loadable<[BlockedUser]> = .loading
    public var errorMessage: String?

    @ObservationIgnored private let repository: any AccountRepository

    public init(repository: any AccountRepository) {
        self.repository = repository
    }

    public func loadTwoFactor() async {
        do {
            twoFactor = .loaded(try await repository.twoFactorStatus())
        } catch {
            twoFactor = .failed(error.message)
        }
    }

    public func loadBlocked() async {
        do {
            blocked = .loaded(try await repository.blockedUsers())
        } catch {
            blocked = .failed(error.message)
        }
    }

    public func unblock(_ user: BlockedUser) async {
        guard case .loaded(var list) = blocked else { return }
        let index = list.firstIndex(of: user)
        list.removeAll { $0.id == user.id }
        blocked = .loaded(list)
        do {
            try await repository.unblock(userId: user.id)
            Log.info(.settings, "Разблокирован пользователь \(user.id)")
        } catch {
            if case .loaded(var now) = blocked, !now.contains(user) {
                now.insert(user, at: min(index ?? 0, now.count))
                blocked = .loaded(now)
            }
            errorMessage = "Не удалось разблокировать. \(error.message)"
        }
    }

    /// После смены почты: новый статус без повторной загрузки.
    public func apply(_ status: TwoFactorStatus) {
        twoFactor = .loaded(status)
    }

    /// Строка «Почта для восстановления»: скрытая почта или `nil`, если её нет.
    public var maskedEmail: String? {
        twoFactor.value?.email.map(TwoFactorStatus.mask(email:))
    }
}

/// Смена почты для восстановления: пароль → почта → код из письма.
@MainActor
@Observable
public final class RecoveryEmailFlow {
    public enum Step: Equatable, Sendable {
        case password
        case email
        case code(email: String)
        case done(TwoFactorStatus)
    }

    public private(set) var step: Step = .password
    public private(set) var isWorking = false
    public var errorMessage: String?
    /// Когда можно выслать код повторно.
    public private(set) var resendAvailableAt: Date?

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var trackId: String?

    public init(repository: any AccountRepository, now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    public func submitPassword(_ password: String) async {
        guard !password.isEmpty else { return }
        await work {
            trackId = try await repository.startEmailChange(password: password)
            step = .email
        }
    }

    public func submitEmail(_ email: String) async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmail(address) else {
            errorMessage = "Проверьте адрес почты"
            return
        }
        guard let trackId else { return }
        await work {
            let wait = try await repository.sendEmailCode(trackId: trackId, email: address)
            resendAvailableAt = now().addingTimeInterval(TimeInterval(max(wait, 0)))
            step = .code(email: address)
        }
    }

    public func resendCode() async {
        guard case .code(let email) = step, canResend else { return }
        guard let trackId else { return }
        await work {
            let wait = try await repository.sendEmailCode(trackId: trackId, email: email)
            resendAvailableAt = now().addingTimeInterval(TimeInterval(max(wait, 0)))
        }
    }

    public var canResend: Bool {
        guard let resendAvailableAt else { return true }
        return now() >= resendAvailableAt
    }

    public func submitCode(_ code: String) async {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty, let trackId else { return }
        await work {
            let status = try await repository.confirmEmail(trackId: trackId, code: digits)
            Log.info(.settings, "Почта для восстановления обновлена")
            step = .done(status)
        }
    }

    /// Вернуться к вводу почты с шага кода.
    public func editEmail() {
        if case .code = step { step = .email }
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !value.contains(" ")
    }

    private func work(_ body: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await body()
        } catch {
            errorMessage = (error as? OrbitleError ?? .unknown).userMessage
        }
    }
}

/// «Устройства»: сеансы, завершение остальных, вход по QR-коду.
@MainActor
@Observable
public final class DevicesModel {
    public private(set) var sessions: Loadable<[DeviceSession]> = .loading
    public private(set) var isClosing = false
    public private(set) var isApproving = false
    public var errorMessage: String?
    /// Сообщение об успехе для короткой плашки.
    public var notice: String?

    @ObservationIgnored private let repository: any AccountRepository

    public init(repository: any AccountRepository) {
        self.repository = repository
    }

    public func load() async {
        do {
            sessions = .loaded(try await repository.sessions())
        } catch {
            sessions = .failed(error.message)
        }
    }

    public var hasOtherSessions: Bool {
        sessions.value?.contains { !$0.isCurrent } ?? false
    }

    public func closeOthers() async {
        isClosing = true
        defer { isClosing = false }
        do {
            try await repository.closeOtherSessions()
            Log.info(.settings, "Остальные сеансы завершены")
            if case .loaded(let list) = sessions {
                sessions = .loaded(list.filter(\.isCurrent))
            }
            notice = "Остальные сеансы завершены"
            await load()
        } catch {
            errorMessage = "Не удалось завершить сеансы. \(error.message)"
        }
    }

    /// Ссылка из QR-кода входа на другом устройстве. `false`, если код не похож на вход в MAX.
    @discardableResult
    public func approve(scanned value: String) async -> Bool {
        guard let link = Self.loginLink(from: value) else {
            errorMessage = "Это не QR-код входа в MAX"
            return false
        }
        isApproving = true
        defer { isApproving = false }
        do {
            try await repository.approveQrLogin(link)
            Log.info(.settings, "Вход по QR-коду подтверждён")
            notice = "Вход подтверждён"
            await load()
            return true
        } catch {
            errorMessage = "Не удалось подтвердить вход. \(error.message)"
            return false
        }
    }

    /// Значение QR-кода входа как есть, без пробелов по краям. Разбирает и проверяет его
    /// сервер (`AUTH_QR_APPROVE`): формат ссылки не документирован, поэтому клиент не
    /// отсеивает коды сам, кроме пустых и явно не ссылок.
    public static func loginLink(from value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        return text
    }
}
