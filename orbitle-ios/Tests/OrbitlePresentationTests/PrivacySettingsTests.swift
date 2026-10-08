import Foundation
import Testing
import OrbitleDomain
@testable import OrbitlePresentation

/// Приватность MAX: отвечает заданным, запоминает запросы.
final class FakePrivacyControls: PrivacyControls, @unchecked Sendable {
    var settingsValue: AccountSettings
    var failWith: OrbitleError?
    private(set) var sent: [(PrivacyKey, PrivacyValue)] = []

    init(_ settings: AccountSettings = AccountSettings(isKnown: true)) {
        settingsValue = settings
    }

    func privacySettings() -> AsyncStream<AccountSettings> {
        let value = settingsValue
        return AsyncStream { $0.yield(value) }
    }

    func setPrivacy(_ key: PrivacyKey, _ value: PrivacyValue) async throws(OrbitleError) -> AccountSettings {
        sent.append((key, value))
        if let failWith { throw failWith }
        settingsValue.set(key, value)
        return settingsValue
    }
}

@MainActor
private func activated(_ controls: FakePrivacyControls) async -> PrivacySettingsModel {
    let model = PrivacySettingsModel(controls: controls)
    model.activate()
    _ = await eventually { model.settings == controls.settingsValue }
    return model
}

@Suite("Приватность MAX: варианты")
struct PrivacyOptionTests {
    @Test("Строки в порядке MAX и их ключи")
    func order() {
        #expect(PrivacyRow.main == [.searchByPhone, .incomingCall, .chatsInvite, .content])
        #expect(PrivacyRow.information == [.onlineStatus, .phoneNumber])
        #expect(PrivacyRow.main.map(\.key.rawValue) == ["SEARCH_BY_PHONE", "INCOMING_CALL", "CHATS_INVITE", "CONTENT_LEVEL_ACCESS"])
        #expect(PrivacyRow.information.map(\.key.rawValue) == ["HIDDEN", "PHONE_NUMBER_PRIVACY"])
        #expect(Set(PrivacyRow.main.map(\.key)) == PrivacyKey.guarded)
    }

    @Test("Подписи вариантов и значения для сервера")
    func mapping() {
        for row in [PrivacyRow.searchByPhone, .incomingCall, .chatsInvite] {
            #expect(row.options.map(\.title) == ["Могут все", "Могут контакты"])
            #expect(row.options.map(\.value.wire) == ["ALL", "CONTACTS"])
        }
        #expect(PrivacyRow.content.options.map(\.title) == ["Весь", "Безопасный"])
        #expect(PrivacyRow.content.options.map(\.value) == [.flag(false), .flag(true)])
        #expect(PrivacyRow.onlineStatus.options.map(\.title) == ["Контакты", "Никто"])
        #expect(PrivacyRow.onlineStatus.options.map(\.value) == [.flag(false), .flag(true)])
        #expect(PrivacyRow.phoneNumber.options.map(\.title) == ["Могут все", "Могут контакты", "Никто"])
        #expect(PrivacyRow.phoneNumber.options.map(\.value.wire) == ["ALL", "CONTACTS", "NOBODY"])
        #expect(PrivacyRow.incomingCall.subtitle == "Кто может мне звонить")
    }

    @Test("Значение вне списка показывается строгим вариантом")
    func outOfList() {
        #expect(PrivacyRow.incomingCall.option(for: .access(.nobody)).title == "Могут контакты")
        #expect(PrivacyRow.chatsInvite.option(for: .access(.nobody)).title == "Могут контакты")
        #expect(PrivacyRow.phoneNumber.option(for: .access(.nobody)).title == "Никто")
    }

    @Test("Подтверждение только для «Никто» у статуса «в сети»")
    func confirmation() {
        let row = PrivacyRow.onlineStatus
        #expect(row.needsConfirmation(row.options[1]))
        #expect(!row.needsConfirmation(row.options[0]))
        #expect(!PrivacyRow.phoneNumber.needsConfirmation(PrivacyRow.phoneNumber.options[2]))
    }

    @Test("Семейная защита читается строкой")
    func family() {
        #expect(FamilyProtection(wire: "ADMIN") == .admin)
        #expect(FamilyProtection(wire: "manageable") == .manageable)
        #expect(FamilyProtection(wire: "OFF") == .off)
        #expect(FamilyProtection(wire: "ON") == .off)
        #expect(FamilyProtection(wire: "") == .off)
        #expect(FamilyProtection.allCases.map(\.title) == ["Отключена", "Вы администратор", "Профиль под защитой"])
    }

    @Test("Значение ключа читается и пишется в настройки")
    func values() {
        var settings = AccountSettings(isKnown: true)
        settings.set(.incomingCall, .access(.contacts))
        settings.set(.contentLevelAccess, .flag(true))
        settings.set(.hidden, .flag(true))
        // Флаг для ключа доступа ничего не меняет.
        settings.set(.searchByPhone, .flag(true))
        #expect(settings.incomingCall == .contacts)
        #expect(settings.safeContentOnly)
        #expect(settings.onlineHidden)
        #expect(settings.searchByPhone == .everybody)
        #expect(settings.value(for: .incomingCall) == .access(.contacts))
        #expect(settings.value(for: .contentLevelAccess) == .flag(true))
    }
}

@MainActor
@Suite("Приватность MAX: экран")
struct PrivacySettingsModelTests {
    @Test("Безопасный режим блокирует четыре строки, «Информация» открыта")
    func safeModeLocks() async {
        let model = await activated(FakePrivacyControls(AccountSettings(isKnown: true, safeMode: true)))
        for row in PrivacyRow.main {
            #expect(model.lockReason(row) == "Отключите безопасный режим, чтобы изменить эту настройку")
            #expect(!model.canChange(row))
        }
        for row in PrivacyRow.information {
            #expect(model.lockReason(row) == nil)
            #expect(model.canChange(row))
        }
        #expect(model.mainLockReason == PrivacySettingsModel.safeModeLock)
    }

    @Test("Профиль под семейной защитой тоже блокирует четыре строки")
    func familyLocks() async {
        let model = await activated(FakePrivacyControls(AccountSettings(isKnown: true, familyProtection: .manageable)))
        for row in PrivacyRow.main {
            #expect(model.lockReason(row) == PrivacySettingsModel.familyLock)
        }
        #expect(model.lockReason(.phoneNumber) == nil)
    }

    @Test("Администратор семейной защиты и обычный профиль ничего не блокируют")
    func unlocked() async {
        for family in [FamilyProtection.off, .admin] {
            let model = await activated(FakePrivacyControls(AccountSettings(isKnown: true, familyProtection: family)))
            #expect(PrivacyRow.allCases.allSatisfy { model.canChange($0) })
            #expect(model.mainLockReason == nil)
        }
    }

    @Test("Пока конфиг неизвестен, менять нельзя, но и блокировки нет")
    func unknown() async {
        let model = PrivacySettingsModel(controls: FakePrivacyControls(.unknown))
        #expect(!model.canChange(.incomingCall))
        #expect(model.lockReason(.incomingCall) == nil)
    }

    @Test("Выбор уходит одним ключом и сразу виден")
    func choose() async {
        let controls = FakePrivacyControls()
        let model = await activated(controls)
        let row = PrivacyRow.incomingCall
        await model.choose(row.options[1], for: row)
        #expect(controls.sent.count == 1)
        #expect(controls.sent.first?.0 == .incomingCall)
        #expect(controls.sent.first?.1 == .access(.contacts))
        #expect(model.settings.incomingCall == .contacts)
        #expect(model.selected(row).title == "Могут контакты")
        // Тот же вариант ещё раз — запроса нет.
        await model.choose(row.options[1], for: row)
        #expect(controls.sent.count == 1)
    }

    @Test("Заблокированную строку выбрать нельзя")
    func lockedChoice() async {
        let controls = FakePrivacyControls(AccountSettings(isKnown: true, safeMode: true, searchByPhone: .contacts))
        let model = await activated(controls)
        await model.choose(PrivacyRow.searchByPhone.options[0], for: .searchByPhone)
        #expect(controls.sent.isEmpty)
        #expect(model.settings.searchByPhone == .contacts)
    }

    @Test("Отказ сервера откатывает только своё поле")
    func rollback() async {
        let controls = FakePrivacyControls()
        let model = await activated(controls)
        controls.failWith = .networkUnavailable
        await model.choose(PrivacyRow.content.options[1], for: .content)
        #expect(!model.settings.safeContentOnly)
        #expect(model.choiceError?.hasPrefix("Не удалось сохранить настройку") == true)
        #expect(model.errorMessage == nil)
        // Безопасный режим сообщает об ошибке алертом экрана.
        await model.setSafeMode(true)
        #expect(!model.settings.safeMode)
        #expect(model.errorMessage != nil)
        // Удачный выбор убирает прежнюю ошибку.
        controls.failWith = nil
        await model.choose(PrivacyRow.content.options[1], for: .content)
        #expect(model.choiceError == nil)
        #expect(model.settings.safeContentOnly)
    }

    @Test("Безопасный режим включается через тот же ключ и блокирует строки")
    func safeModeToggle() async {
        let controls = FakePrivacyControls()
        let model = await activated(controls)
        #expect(model.canChange(.chatsInvite))
        await model.setSafeMode(true)
        #expect(controls.sent.last?.0 == .safeMode)
        #expect(controls.sent.last?.1 == .flag(true))
        #expect(!model.canChange(.chatsInvite))
    }
}
