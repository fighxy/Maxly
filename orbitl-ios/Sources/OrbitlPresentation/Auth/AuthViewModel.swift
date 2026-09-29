import Foundation
import Observation
import OrbitlDomain

/// Экран входа: номер, код из SMS, пароль 2FA и регистрация.
///
/// Шаг приходит из потока `AuthService.phases()`. Вся проверка ввода, маска номера,
/// таймер повторной отправки и тексты живут здесь, чтобы экран оставался тонким и
/// тестировался без приложения. Таймер не тикает сам: экран перерисовывается
/// раз в секунду (`TimelineView`) и спрашивает `resendSecondsLeft(at:)`.
@MainActor
@Observable
public final class AuthViewModel {
    public enum Step: Equatable, Sendable {
        case phone
        case code(length: Int?)
        case password(hint: String?)
        case registration
    }

    /// Сколько секунд ждать перед повторной отправкой кода. Столько же ждёт
    /// официальный клиент Max (и Komet), раньше сервер повтор всё равно не пустит.
    public static let defaultResendInterval: TimeInterval = 30
    static let maxCodeLength = 8
    static let maxNameLength = 60

    public private(set) var step: Step = .phone
    public private(set) var isBusy = false
    public private(set) var error: OrbitlError?
    /// Сервер отклонил сохранённый токен: экран объясняет, почему снова вход.
    public private(set) var sessionExpired = false
    /// Номер (E.164), на который ушёл код.
    public private(set) var sentTo: String?
    /// Когда можно запросить код повторно.
    public private(set) var resendAvailableAt: Date?

    private var phoneText = ""
    private var codeText = ""

    /// Номер в поле ввода, всегда с маской `+7 999 123-45-67`.
    public var phone: String {
        get { phoneText }
        set {
            let edited = PhoneNumber.edit(from: phoneText, to: newValue)
            guard edited != phoneText else { return }
            phoneText = edited
            error = nil
        }
    }

    /// Код из SMS: только цифры, не длиннее ожидаемого. Полный код отправляется сам.
    public var code: String {
        get { codeText }
        set {
            let digits = String(newValue.filter(\.isASCIIDigit).prefix(expectedCodeLength ?? Self.maxCodeLength))
            guard digits != codeText else { return }
            codeText = digits
            error = nil
            if let expected = expectedCodeLength, digits.count == expected, !isBusy {
                pendingAutoSubmit = Task { [weak self] in await self?.verify() }
            }
        }
    }

    public var password = "" {
        didSet { if password != oldValue { error = nil } }
    }

    public var firstName = "" {
        didSet { if firstName != oldValue { error = nil } }
    }

    public var lastName = "" {
        didSet { if lastName != oldValue { error = nil } }
    }

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let resendInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<OrbitlError?, Never>?
    /// Автоотправка полного кода. Внутренний доступ — чтобы тесты дожидались её, а не спали.
    @ObservationIgnored private(set) var pendingAutoSubmit: Task<Void, Never>?

    public init(
        auth: any AuthService,
        resendInterval: TimeInterval = AuthViewModel.defaultResendInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.auth = auth
        self.resendInterval = resendInterval
        self.now = now
    }

    // MARK: Состояние для экрана

    public var title: String {
        switch step {
        case .phone: "Вход"
        case .code: "Код из SMS"
        case .password: "Пароль"
        case .registration: "Новый аккаунт"
        }
    }

    public var normalizedPhone: String? { PhoneNumber.normalized(phoneText) }

    /// Подсказка под полем номера, когда цифр уже достаточно, а номер не распознан.
    public var phoneHint: String? {
        let digits = phoneText.filter(\.isASCIIDigit).count
        guard normalizedPhone == nil, digits >= 11 || (phoneText.hasPrefix("+") && !phoneText.hasPrefix("+7") && digits >= 8) else {
            return nil
        }
        return "Проверьте номер: например, +7 900 000-00-00"
    }

    public var canRequestCode: Bool { !isBusy && normalizedPhone != nil }

    /// Ожидаемая длина кода на шаге кода.
    public var expectedCodeLength: Int? {
        guard case .code(let length) = step else { return nil }
        return length
    }

    public var codePrompt: String {
        let number = sentTo.map(PhoneNumber.display) ?? "ваш номер"
        if let length = expectedCodeLength {
            return "Мы отправили код из \(length) цифр на \(number)"
        }
        return "Мы отправили код на \(number)"
    }

    public var canVerify: Bool {
        guard !isBusy, case .code = step else { return false }
        if let expected = expectedCodeLength { return codeText.count == expected }
        return codeText.count >= 4
    }

    public var passwordPrompt: String {
        if case .password(let hint?) = step, !hint.isEmpty {
            return "Аккаунт защищён облачным паролем. Подсказка: \(hint)"
        }
        return "Аккаунт защищён облачным паролем"
    }

    public var canSubmitPassword: Bool {
        guard case .password = step else { return false }
        return !isBusy && !password.isEmpty
    }

    public var canRegister: Bool {
        guard case .registration = step else { return false }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isBusy && !first.isEmpty && first.count <= Self.maxNameLength && lastName.count <= Self.maxNameLength
    }

    public var canGoBack: Bool { step != .phone }

    public var errorMessage: String? { error?.userMessage }

    /// Сколько секунд осталось до повторной отправки кода.
    public func resendSecondsLeft(at date: Date) -> Int {
        guard let resendAvailableAt else { return 0 }
        return max(0, Int(resendAvailableAt.timeIntervalSince(date).rounded(.up)))
    }

    public func canResend(at date: Date) -> Bool {
        guard case .code = step else { return false }
        return !isBusy && resendSecondsLeft(at: date) == 0
    }

    public func resendTitle(at date: Date) -> String {
        let left = resendSecondsLeft(at: date)
        guard left > 0 else { return "Отправить код ещё раз" }
        return "Отправить ещё раз через \(left / 60):\(String(format: "%02d", left % 60))"
    }

    // MARK: Жизненный цикл

    /// Подписка на шаги входа. Повторный вызов ничего не делает.
    public func activate() {
        guard watch == nil else { return }
        let phases = auth.phases()
        watch = Task { [weak self] in
            for await phase in phases {
                guard let self else { return }
                self.apply(phase)
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
    }

    // MARK: Действия

    public func requestCode() async {
        guard !isBusy else { return }
        guard let number = normalizedPhone else {
            error = .rejected("Введите номер в формате +7 900 000-00-00")
            return
        }
        let auth = auth
        let succeeded = await perform { () async throws(OrbitlError) in try await auth.requestCode(phone: number) }
        guard succeeded else { return }
        sentTo = number
        codeText = ""
        sessionExpired = false
        resendAvailableAt = now().addingTimeInterval(resendInterval)
    }

    public func resendCode() async {
        guard canResend(at: now()) else { return }
        let auth = auth
        let succeeded = await perform { () async throws(OrbitlError) in try await auth.resendCode() }
        guard succeeded else { return }
        codeText = ""
        resendAvailableAt = now().addingTimeInterval(resendInterval)
    }

    public func verify() async {
        guard canVerify else { return }
        let auth = auth
        let code = codeText
        let succeeded = await perform { () async throws(OrbitlError) in try await auth.verifyCode(code) }
        if !succeeded, error == .codeRenewed {
            // Сервис уже выслал новый код: таймер повтора начинается заново.
            resendAvailableAt = now().addingTimeInterval(resendInterval)
        }
        if !succeeded, case .rejected = error {
            // Неверный код стирается, чтобы набрать новый без лишних действий.
            codeText = ""
        }
    }

    public func submitPassword() async {
        guard canSubmitPassword else { return }
        let auth = auth
        let password = password
        let succeeded = await perform { () async throws(OrbitlError) in try await auth.submitPassword(password) }
        if !succeeded, case .rejected = error {
            let failure = error
            self.password = ""
            error = failure
        }
    }

    public func register() async {
        guard case .registration = step, !isBusy else { return }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else {
            error = .rejected("Введите имя")
            return
        }
        guard first.count <= Self.maxNameLength, last.count <= Self.maxNameLength else {
            error = .rejected("Имя и фамилия не длиннее \(Self.maxNameLength) символов")
            return
        }
        let auth = auth
        _ = await perform { () async throws(OrbitlError) in try await auth.register(firstName: first, lastName: last) }
    }

    /// Назад к вводу номера. Идущий запрос отменяется, его поздний ответ шаг не меняет.
    public func goBack() async {
        guard step != .phone else { return }
        operation?.cancel()
        operation = nil
        pendingAutoSubmit?.cancel()
        pendingAutoSubmit = nil
        isBusy = false
        error = nil
        resetSecrets()
        resendAvailableAt = nil
        sentTo = nil
        step = .phone
        await auth.cancelLogin()
    }

    // MARK: Внутреннее

    func apply(_ phase: AuthPhase) {
        switch phase {
        case .restoring:
            break
        case .signedOut:
            if step != .phone {
                resetSecrets()
                resendAvailableAt = nil
                step = .phone
            }
        case .expired:
            sessionExpired = true
            resetSecrets()
            resendAvailableAt = nil
            step = .phone
        case .codeSent(let length):
            if step != .code(length: length) {
                step = .code(length: length)
                codeText = String(codeText.prefix(length ?? Self.maxCodeLength))
            }
            if resendAvailableAt == nil {
                resendAvailableAt = now().addingTimeInterval(resendInterval)
            }
        case .password(let hint):
            if step != .password(hint: hint) {
                password = ""
                step = .password(hint: hint)
            }
        case .registration:
            step = .registration
        case .signedIn:
            sessionExpired = false
            resetSecrets()
        }
    }

    private func resetSecrets() {
        codeText = ""
        password = ""
    }

    /// Запускает вызов сервиса как отменяемую задачу. `true`, если вызов прошёл
    /// и его не заменило действие «назад». Отмену экран не показывает.
    private func perform(_ body: @escaping @Sendable () async throws(OrbitlError) -> Void) async -> Bool {
        isBusy = true
        error = nil
        let task = Task { () async -> OrbitlError? in
            do throws(OrbitlError) {
                try await body()
                return nil
            } catch {
                return error
            }
        }
        operation = task
        let failure = await task.value
        guard operation == task else { return false }
        operation = nil
        isBusy = false
        if let failure {
            error = failure == .cancelled ? nil : failure
            return false
        }
        return true
    }
}
