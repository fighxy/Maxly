import Foundation
import Observation
import OrbitleDomain

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
    public private(set) var error: OrbitleError?
    /// Сервер отклонил сохранённый токен: экран объясняет, почему снова вход.
    public private(set) var sessionExpired = false
    /// Номер (E.164), на который ушёл код.
    public private(set) var sentTo: String?
    /// Когда можно запросить код повторно.
    public private(set) var resendAvailableAt: Date?

    /// Код страны без плюса и цифры национальной части. Из них собирается номер.
    private var countryDigits = PhoneCountry.russia.code
    private var nationalDigits = ""
    private var codeText = ""

    /// Страна номера. `nil`, если такого кода нет в списке.
    public private(set) var country: PhoneCountry? = .russia

    /// Номер одной строкой с маской `+7 999 123-45-67` (для `+7`) или `+375…`.
    /// Запись разбирает строку на код страны и номер.
    public var phone: String {
        get { phoneText }
        set {
            let edited = PhoneNumber.edit(from: phoneText, to: newValue)
            guard edited != phoneText else { return }
            split(edited)
            error = nil
        }
    }

    /// Поле кода страны: только цифры, до четырёх. Вставленный целиком номер разбирается.
    public var countryCode: String {
        get { countryDigits }
        set {
            let digits = String(newValue.filter(\.isASCIIDigit))
            if digits.count > 4 {
                split(PhoneNumber.formatted("+" + digits))
                error = nil
                return
            }
            guard digits != countryDigits else { return }
            countryDigits = digits
            syncCountry()
            nationalDigits = String(nationalDigits.prefix(maxNationalDigits))
            error = nil
        }
    }

    /// Поле номера без кода, с маской страны (`999 123 4567`).
    public var nationalNumber: String {
        get { formatNational(nationalDigits) }
        set {
            if newValue.hasPrefix("+") {
                // Автозаполнение или вставка номера целиком, с кодом страны.
                split(PhoneNumber.formatted(newValue))
                error = nil
                return
            }
            var digits = String(newValue.filter(\.isASCIIDigit))
            let old = formatNational(nationalDigits)
            if newValue.count < old.count, digits == nationalDigits, !digits.isEmpty {
                // Стёрли разделитель: убираем цифру перед ним.
                digits.removeLast()
            } else if countryDigits == PhoneCountry.russia.code, digits.count == 11, digits.first == "8" || digits.first == "7",
                      !(nationalDigits.count == maxNationalDigits && digits.hasPrefix(nationalDigits)) {
                // Российский номер целиком: `8 999 …` или `7 999 …`. Лишняя цифра после
                // полного номера на `7…` или `8…` (Казахстан, 800) его не сдвигает.
                digits.removeFirst()
            }
            digits = String(digits.prefix(maxNationalDigits))
            guard digits != nationalDigits else { return }
            nationalDigits = digits
            error = nil
        }
    }

    /// Серый пример номера в пустом поле.
    public var phonePlaceholder: String { country?.pattern ?? "000 000 0000" }

    /// Строка страны над полем номера. Код не из списка тоже принимается:
    /// список стран неполный, а номер проверят общие правила E.164.
    public var countryTitle: String {
        if let country { return country.name }
        return countryDigits.isEmpty ? "Выберите страну" : "Другая страна"
    }

    /// Код набран до конца: экран может перевести курсор в поле номера.
    public var isCountryCodeComplete: Bool { PhoneCountry.isComplete(code: countryDigits) }

    public func selectCountry(_ selected: PhoneCountry) {
        country = selected
        countryDigits = selected.code
        nationalDigits = String(nationalDigits.prefix(maxNationalDigits))
        error = nil
    }

    private var phoneText: String {
        if countryDigits == PhoneCountry.russia.code {
            return nationalDigits.isEmpty ? "" : PhoneNumber.formatted("+7" + nationalDigits)
        }
        if countryDigits.isEmpty, nationalDigits.isEmpty { return "" }
        return "+" + countryDigits + nationalDigits
    }

    private var maxNationalDigits: Int {
        if let country { return country.maxDigits }
        return max(0, 15 - countryDigits.count)
    }

    private func formatNational(_ digits: String) -> String {
        guard let country else { return digits }
        return country.format(digits)
    }

    /// Разбирает номер одной строкой (маска `PhoneNumber`) на код и национальную часть.
    private func split(_ formatted: String) {
        let digits = String(formatted.filter(\.isASCIIDigit))
        if formatted.isEmpty {
            countryDigits = country?.code ?? PhoneCountry.russia.code
            nationalDigits = ""
        } else if formatted.hasPrefix("+7") || !formatted.hasPrefix("+") {
            countryDigits = "7"
            nationalDigits = String(digits.dropFirst())
        } else {
            let code = PhoneCountry.longestCode(in: digits) ?? String(digits.prefix(3))
            countryDigits = code
            nationalDigits = String(digits.dropFirst(code.count))
        }
        syncCountry()
        nationalDigits = String(nationalDigits.prefix(maxNationalDigits))
    }

    /// Страна под код. Уже выбранная страна с тем же кодом (Казахстан для `+7`) остаётся.
    private func syncCountry() {
        if country?.code == countryDigits { return }
        country = PhoneCountry.preferred(forCode: countryDigits)
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

    /// Фото профиля, выбранное при регистрации. Ядро пока не умеет загружать фото,
    /// поэтому оно только показывается на экране и живёт до конца попытки входа.
    public var registrationPhoto: Data?

    /// Сколько ячеек показать на шаге кода: длина от сервера, иначе шесть и больше,
    /// если набрано длиннее.
    public var codeCellCount: Int { expectedCodeLength ?? max(6, codeText.count) }

    /// Сервер не сообщил длину кода: автоотправки нет, экран показывает кнопку.
    public var needsManualCodeSubmit: Bool {
        guard case .code(nil) = step else { return false }
        return true
    }

    /// Номер, на который ушёл код, в виде для экрана.
    public var sentToDisplay: String? { sentTo.map(PhoneNumber.display) }

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let resendInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<OrbitleError?, Never>?
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

    /// Номер в E.164 или `nil`, если он неполный. Для `+7` действуют российские правила,
    /// для известной страны — длина её номеров, для неизвестного кода — общие 8–15 цифр.
    public var normalizedPhone: String? {
        if countryDigits == PhoneCountry.russia.code {
            return PhoneNumber.normalized("+7" + nationalDigits)
        }
        guard !countryDigits.isEmpty, countryDigits.first != "0" else { return nil }
        if let country {
            guard (country.minDigits...country.maxDigits).contains(nationalDigits.count) else { return nil }
            return "+" + countryDigits + nationalDigits
        }
        return PhoneNumber.normalized("+" + countryDigits + nationalDigits)
    }

    /// Подсказка под полем номера, когда цифр уже достаточно, а номер не распознан.
    public var phoneHint: String? {
        guard normalizedPhone == nil else { return nil }
        if countryDigits == PhoneCountry.russia.code {
            guard nationalDigits.count >= 10 else { return nil }
            return "Проверьте номер: например, +7 900 000-00-00"
        }
        if country == nil, !countryDigits.isEmpty, nationalDigits.count >= 6 {
            return "Проверьте код страны"
        }
        return nil
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
        return "Отправить код ещё раз через \(left / 60):\(String(format: "%02d", left % 60))"
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
            error = .rejected(countryDigits == PhoneCountry.russia.code ? "Введите номер в формате +7 900 000-00-00" : "Проверьте код страны и номер")
            return
        }
        let auth = auth
        let succeeded = await perform { () async throws(OrbitleError) in try await auth.requestCode(phone: number) }
        guard succeeded else { return }
        sentTo = number
        codeText = ""
        sessionExpired = false
        resendAvailableAt = now().addingTimeInterval(resendInterval)
    }

    public func resendCode() async {
        guard canResend(at: now()) else { return }
        let auth = auth
        let succeeded = await perform { () async throws(OrbitleError) in try await auth.resendCode() }
        guard succeeded else { return }
        codeText = ""
        resendAvailableAt = now().addingTimeInterval(resendInterval)
    }

    public func verify() async {
        guard canVerify else { return }
        let auth = auth
        let code = codeText
        let succeeded = await perform { () async throws(OrbitleError) in try await auth.verifyCode(code) }
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
        let succeeded = await perform { () async throws(OrbitleError) in try await auth.submitPassword(password) }
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
        _ = await perform { () async throws(OrbitleError) in try await auth.register(firstName: first, lastName: last) }
    }

    /// Назад к вводу номера. Идущий запрос отменяется, его поздний ответ шаг не меняет.
    public func goBack() async {
        guard resetToPhone() else { return }
        await auth.cancelLogin()
    }

    /// То же, что `goBack()`, но шаг меняется сразу. Для системной кнопки «назад»:
    /// стек навигации должен совпасть с шагом до следующей отрисовки.
    public func backToPhone() {
        guard resetToPhone() else { return }
        let auth = auth
        Task { await auth.cancelLogin() }
    }

    private func resetToPhone() -> Bool {
        guard step != .phone else { return false }
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
        return true
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
        registrationPhoto = nil
    }

    /// Запускает вызов сервиса как отменяемую задачу. `true`, если вызов прошёл
    /// и его не заменило действие «назад». Отмену экран не показывает.
    private func perform(_ body: @escaping @Sendable () async throws(OrbitleError) -> Void) async -> Bool {
        isBusy = true
        error = nil
        let task = Task { () async -> OrbitleError? in
            do throws(OrbitleError) {
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
