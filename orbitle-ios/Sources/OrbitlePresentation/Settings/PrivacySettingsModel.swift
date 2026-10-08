import Foundation
import Observation
import OrbitleDomain

/// Вариант в списке выбора: подпись и значение для сервера.
public struct PrivacyOption: Hashable, Sendable, Identifiable {
    public let title: String
    public let value: PrivacyValue

    public init(_ title: String, _ value: PrivacyValue) {
        self.title = title
        self.value = value
    }

    public var id: String { value.wire }
}

/// Строки приватности MAX под «Безопасным режимом» и в секции «Информация», в порядке MAX.
public enum PrivacyRow: String, CaseIterable, Sendable, Identifiable {
    case searchByPhone
    case incomingCall
    case chatsInvite
    case content
    case onlineStatus
    case phoneNumber

    public var id: String { rawValue }

    /// Четыре строки под безопасным режимом.
    public static let main: [PrivacyRow] = [.searchByPhone, .incomingCall, .chatsInvite, .content]
    /// Секция «Информация».
    public static let information: [PrivacyRow] = [.onlineStatus, .phoneNumber]

    public var key: PrivacyKey {
        switch self {
        case .searchByPhone: .searchByPhone
        case .incomingCall: .incomingCall
        case .chatsInvite: .chatsInvite
        case .content: .contentLevelAccess
        case .onlineStatus: .hidden
        case .phoneNumber: .phoneNumberPrivacy
        }
    }

    public var title: String {
        switch self {
        case .searchByPhone: "Найти меня по номеру"
        case .incomingCall: "Позвонить"
        case .chatsInvite: "Пригласить в чат"
        case .content: "Показывать контент"
        case .onlineStatus: "Видеть статус «в сети»"
        case .phoneNumber: "Видеть мой номер"
        }
    }

    /// Подзаголовок над списком вариантов.
    public var subtitle: String {
        switch self {
        case .searchByPhone: "Кто может найти меня по номеру телефона"
        case .incomingCall: "Кто может мне звонить"
        case .chatsInvite: "Кто может пригласить меня в чат"
        case .content: "Какой контент мне показывать"
        case .onlineStatus: "Кто может видеть, когда я в сети"
        case .phoneNumber: "Кто может видеть мой номер телефона"
        }
    }

    /// Пояснение под списком вариантов.
    public var footer: String? {
        switch self {
        case .content: "Безопасный скрывает каналы и материалы 16+ и 18+, в том числе в поиске и рекомендациях."
        case .onlineStatus: "Если выбрать «Никто», вы тоже перестанете видеть, кто в сети."
        default: nil
        }
    }

    public var options: [PrivacyOption] {
        switch self {
        case .searchByPhone, .incomingCall, .chatsInvite:
            [PrivacyOption("Могут все", .access(.everybody)), PrivacyOption("Могут контакты", .access(.contacts))]
        case .content:
            [PrivacyOption("Весь", .flag(false)), PrivacyOption("Безопасный", .flag(true))]
        case .onlineStatus:
            [PrivacyOption("Контакты", .flag(false)), PrivacyOption("Никто", .flag(true))]
        case .phoneNumber:
            [
                PrivacyOption("Могут все", .access(.everybody)),
                PrivacyOption("Могут контакты", .access(.contacts)),
                PrivacyOption("Никто", .access(.nobody)),
            ]
        }
    }

    /// Вариант для значения. Значение вне списка (например `NOBODY` у звонков) — ближайший
    /// строгий вариант списка: «Могут контакты».
    public func option(for value: PrivacyValue) -> PrivacyOption {
        if let exact = options.first(where: { $0.value == value }) { return exact }
        return options.last ?? PrivacyOption("", value)
    }

    /// Выбор требует подтверждения: скрыть статус «в сети» от всех.
    public func needsConfirmation(_ option: PrivacyOption) -> Bool {
        self == .onlineStatus && option.value == .flag(true)
    }
}

/// «Конфиденциальность» в «Безопасности»: безопасный режим и строки MAX (docs/privacy.md).
///
/// Выбор применяется сразу и откатывается, если сервер отказал. Пока включён безопасный режим
/// или профилем управляет семейная защита, четыре строки под переключателем заблокированы.
@MainActor
@Observable
public final class PrivacySettingsModel {
    public static let safeModeLock = "Отключите безопасный режим, чтобы изменить эту настройку"
    public static let familyLock = "Этой настройкой управляет семейная защита"

    public private(set) var settings: AccountSettings = .unknown
    /// Ошибка безопасного режима: алерт экрана «Безопасность».
    public var errorMessage: String?
    /// Ошибка выбора в списке вариантов: текст под списком, пока экран открыт.
    public var choiceError: String?
    /// Настройки без сеттера в ядре пока только запоминаются на устройстве (заглушка).
    public let isLocalOnly: Bool

    @ObservationIgnored private let controls: any PrivacyControls
    @ObservationIgnored private var watch: Task<Void, Never>?

    public init(controls: any PrivacyControls, isLocalOnly: Bool = false) {
        self.controls = controls
        self.isLocalOnly = isLocalOnly
    }

    public func activate() {
        guard watch == nil else { return }
        let stream = controls.privacySettings()
        watch = Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                self.settings = value
            }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
    }

    public var familyProtection: FamilyProtection { settings.familyProtection }

    /// Почему строку нельзя менять. `nil` — можно.
    public func lockReason(_ row: PrivacyRow) -> String? {
        guard PrivacyKey.guarded.contains(row.key) else { return nil }
        if settings.safeMode { return Self.safeModeLock }
        if settings.familyProtection == .manageable { return Self.familyLock }
        return nil
    }

    public func isLocked(_ row: PrivacyRow) -> Bool {
        lockReason(row) != nil
    }

    /// Строку можно открыть: конфиг пришёл и строка не заблокирована.
    public func canChange(_ row: PrivacyRow) -> Bool {
        settings.isKnown && !isLocked(row)
    }

    /// Причина блокировки четырёх строк под безопасным режимом, для пояснения под секцией.
    public var mainLockReason: String? {
        PrivacyRow.main.lazy.compactMap { self.lockReason($0) }.first
    }

    public func selected(_ row: PrivacyRow) -> PrivacyOption {
        row.option(for: settings.value(for: row.key))
    }

    public func choose(_ option: PrivacyOption, for row: PrivacyRow) async {
        guard canChange(row) else { return }
        choiceError = nil
        choiceError = await change(row.key, to: option.value)
    }

    public func setSafeMode(_ enabled: Bool) async {
        guard settings.isKnown else { return }
        if let failure = await change(.safeMode, to: .flag(enabled)) { errorMessage = failure }
    }

    /// Текст ошибки для экрана; `nil` — сохранено (или нечего сохранять).
    private func change(_ key: PrivacyKey, to value: PrivacyValue) async -> String? {
        let before = settings.value(for: key)
        guard before != value else { return nil }
        settings.set(key, value)
        do {
            settings = try await controls.setPrivacy(key, value)
            Log.info(.settings, "\(key.rawValue) = \(value.wire)")
            return nil
        } catch {
            // Только своё поле: остальное могло за это время прийти с сервера.
            settings.set(key, before)
            return error.userMessage.map { "Не удалось сохранить настройку. \($0)" }
        }
    }
}
