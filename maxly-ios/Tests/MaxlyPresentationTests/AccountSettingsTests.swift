import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

/// Фейк аккаунта: отвечает заданным, считает вызовы.
final class FakeAccountRepository: AccountRepository, @unchecked Sendable {
    var profileValue = MyProfile(id: "1", firstName: "Иван", lastName: "Петров", phone: "79990001122")
    var settingsValue = AccountSettings(isKnown: true)
    var failWith: MaxlyError?
    var sessionsValue: [DeviceSession] = []
    var blockedValue: [BlockedUser] = []
    var approved: [String] = []
    var closedOthers = 0
    var unblocked: [String] = []
    var emailCodes: [(String, String)] = []
    var confirmedCode: String?
    var launched: [MiniApp.Kind] = []

    func check() throws(MaxlyError) { if let failWith { throw failWith } }

    func profile() async throws(MaxlyError) -> MyProfile { try check(); return profileValue }
    func updateProfile(firstName: String, lastName: String, about: String) async throws(MaxlyError) -> MyProfile {
        try check()
        profileValue.firstName = firstName
        profileValue.lastName = lastName
        profileValue.about = about
        return profileValue
    }
    func uploadAvatar(jpeg: Data) async throws(MaxlyError) -> MyProfile {
        try check()
        profileValue.hasPhoto = true
        return profileValue
    }
    func removeAvatar() async throws(MaxlyError) -> MyProfile {
        try check()
        profileValue.hasPhoto = false
        return profileValue
    }
    func deleteAccount() async throws(MaxlyError) -> Date? { try check(); return nil }
    func settings() -> AsyncStream<AccountSettings> {
        let value = settingsValue
        return AsyncStream { $0.yield(value) }
    }
    func setPhonePrivacy(_ access: PrivacyAccess) async throws(MaxlyError) -> AccountSettings {
        try check(); settingsValue.phonePrivacy = access; return settingsValue
    }
    func setOnlineHidden(_ hidden: Bool) async throws(MaxlyError) -> AccountSettings {
        try check(); settingsValue.onlineHidden = hidden; return settingsValue
    }
    func setSafeMode(_ enabled: Bool) async throws(MaxlyError) -> AccountSettings {
        try check(); settingsValue.safeMode = enabled; return settingsValue
    }
    func setInactiveTTL(_ ttl: InactiveTTL) async throws(MaxlyError) -> AccountSettings {
        try check(); settingsValue.inactiveTTL = ttl; return settingsValue
    }
    var quickReactions: [String] = []
    func setQuickReaction(_ emoji: String) async throws(MaxlyError) -> AccountSettings {
        try check()
        quickReactions.append(emoji)
        settingsValue.quickReaction = emoji
        settingsValue.quickReactionEnabled = true
        return settingsValue
    }
    func sessions() async throws(MaxlyError) -> [DeviceSession] { try check(); return sessionsValue }
    func closeOtherSessions() async throws(MaxlyError) {
        try check()
        closedOthers += 1
        sessionsValue = sessionsValue.filter(\.isCurrent)
    }
    func approveQrLogin(_ link: String) async throws(MaxlyError) { try check(); approved.append(link) }
    func blockedUsers() async throws(MaxlyError) -> [BlockedUser] { try check(); return blockedValue }
    func unblock(userId: String) async throws(MaxlyError) { try check(); unblocked.append(userId) }
    func twoFactorStatus() async throws(MaxlyError) -> TwoFactorStatus { try check(); return TwoFactorStatus(isEnabled: true) }
    func startEmailChange(password: String) async throws(MaxlyError) -> String {
        if password != "secret" { throw .rejected("Неверный пароль") }
        return "track"
    }
    func sendEmailCode(trackId: String, email: String) async throws(MaxlyError) -> Int {
        try check(); emailCodes.append((trackId, email)); return 60
    }
    func confirmEmail(trackId: String, code: String) async throws(MaxlyError) -> TwoFactorStatus {
        try check(); confirmedCode = code; return TwoFactorStatus(isEnabled: true, email: "ivan@ya.ru")
    }
    func launchMiniApp(_ kind: MiniApp.Kind) async throws(MaxlyError) -> MiniApp {
        try check(); launched.append(kind)
        return MiniApp(botId: kind == .sferum ? 2_340_831 : 8_250_447, url: URL(string: "https://app.example/\(kind.rawValue)")!)
    }
    func miniAppCallback(url: URL) async throws(MaxlyError) -> MiniApp {
        try check()
        return MiniApp(botId: 8_250_447, url: URL(string: "https://app.example/after")!)
    }
}

@Suite("Настройки аккаунта")
@MainActor
struct AccountSettingsTests {
    @Test("Номер в шапке скрыт, пока не нажат глаз")
    func phoneReveal() async {
        let model = AccountSettingsModel(repository: FakeAccountRepository())
        await model.activate()
        #expect(model.headerPhone == "+7 ••• •••-••-••")
        model.isPhoneRevealed = true
        #expect(model.headerPhone == "+7 999 000-11-22")
        model.deactivate()
    }

    @Test("Переключатель меняется сразу и откатывается при отказе сервера")
    func optimisticToggle() async {
        let repo = FakeAccountRepository()
        let model = AccountSettingsModel(repository: repo)
        await model.setSafeMode(true)
        #expect(model.settings.safeMode)
        repo.failWith = .networkUnavailable
        await model.setPhonePrivacy(.nobody)
        // Откат к прежнему значению: по умолчанию номер видят контакты, как в веб-клиенте MAX.
        #expect(model.settings.phonePrivacy == .contacts)
        #expect(model.errorMessage != nil)
        #expect(model.settings.safeMode)
    }

    @Test("Профиль без имени не сохраняется")
    func saveProfile() async {
        let repo = FakeAccountRepository()
        let model = AccountSettingsModel(repository: repo)
        #expect(await model.saveProfile(firstName: "  ", lastName: "", about: "") == false)
        #expect(model.errorMessage == "Укажите имя")
        #expect(await model.saveProfile(firstName: " Пётр ", lastName: "Иванов ", about: " Привет ") == true)
        #expect(model.profile?.firstName == "Пётр")
        #expect(model.profile?.about == "Привет")
    }

    @Test("Фото загружается и удаляется")
    func photo() async {
        let model = AccountSettingsModel(repository: FakeAccountRepository())
        await model.uploadPhoto(jpeg: Data([1, 2, 3]))
        #expect(model.hasPhoto)
        await model.removePhoto()
        #expect(!model.hasPhoto)
    }
}

@Suite("Безопасность и устройства")
@MainActor
struct SecurityDevicesTests {
    @Test("Смена почты: пароль, почта, код")
    func emailFlow() async {
        let repo = FakeAccountRepository()
        let flow = RecoveryEmailFlow(repository: repo, now: { Date(timeIntervalSince1970: 0) })
        await flow.submitPassword("wrong")
        #expect(flow.step == .password)
        #expect(flow.errorMessage == "Неверный пароль")
        await flow.submitPassword("secret")
        #expect(flow.step == .email)
        await flow.submitEmail("не почта")
        #expect(flow.step == .email)
        await flow.submitEmail(" ivan@ya.ru ")
        #expect(flow.step == .code(email: "ivan@ya.ru"))
        #expect(repo.emailCodes.first?.0 == "track")
        #expect(!flow.canResend)
        await flow.submitCode("12-34-56")
        #expect(repo.confirmedCode == "123456")
        #expect(flow.step == .done(TwoFactorStatus(isEnabled: true, email: "ivan@ya.ru")))
    }

    @Test("Разблокировка убирает из списка, отказ возвращает")
    func unblock() async {
        let repo = FakeAccountRepository()
        let user = BlockedUser(id: "7", name: "Спамер")
        repo.blockedValue = [user, BlockedUser(id: "8", name: "Ещё")]
        let model = SecuritySettingsModel(repository: repo)
        await model.loadBlocked()
        await model.unblock(user)
        #expect(model.blocked.value?.map(\.id) == ["8"])
        #expect(repo.unblocked == ["7"])
        repo.failWith = .networkUnavailable
        await model.unblock(BlockedUser(id: "8", name: "Ещё"))
        #expect(model.blocked.value?.map(\.id) == ["8"])
    }

    @Test("Завершить остальные сеансы оставляет текущий")
    func closeOthers() async {
        let repo = FakeAccountRepository()
        repo.sessionsValue = [DeviceSession(id: "1", client: "iOS", isCurrent: true), DeviceSession(id: "2", client: "Web")]
        let model = DevicesModel(repository: repo)
        await model.load()
        #expect(model.hasOtherSessions)
        await model.closeOthers()
        #expect(repo.closedOthers == 1)
        #expect(model.sessions.value?.map(\.id) == ["1"])
        #expect(!model.hasOtherSessions)
    }

    @Test("QR-код входа уходит на сервер как есть, мусор — нет")
    func qr() async {
        let repo = FakeAccountRepository()
        let model = DevicesModel(repository: repo)
        #expect(await model.approve(scanned: "  ") == false)
        #expect(await model.approve(scanned: "not a link") == false)
        #expect(await model.approve(scanned: " https://max.ru/:auth/abc ") == true)
        #expect(repo.approved == ["https://max.ru/:auth/abc"])
    }
}

/// Фейк серверных папок.
final class FakeFolderRepository: FolderRepository, @unchecked Sendable {
    var list: [ServerFolder] = [
        ServerFolder(id: "all.chat.folder", title: "Все", isAllChats: true),
        ServerFolder(id: "a", title: "Работа", chatIds: ["1"]),
        ServerFolder(id: "b", title: "Семья"),
    ]
    var created: [(String, [String], [String])] = []
    var reordered: [[String]] = []
    var deleted: [String] = []
    var failWith: MaxlyError?

    func folders() -> AsyncStream<[ServerFolder]> {
        let list = list
        return AsyncStream { $0.yield(list) }
    }
    func reload() async throws(MaxlyError) {}
    func create(title: String, chatIds: [String], filters: [String]) async throws(MaxlyError) {
        if let failWith { throw failWith }
        created.append((title, chatIds, filters))
    }
    func rename(folderId: String, title: String) async throws(MaxlyError) {}
    func setChats(folderId: String, chatIds: [String]) async throws(MaxlyError) {}
    func delete(folderId: String) async throws(MaxlyError) {
        if let failWith { throw failWith }
        deleted.append(folderId)
    }
    func reorder(_ folderIds: [String]) async throws(MaxlyError) {
        if let failWith { throw failWith }
        reordered.append(folderIds)
    }
}

@Suite("Папки")
@MainActor
struct FoldersModelTests {
    private func loaded(_ repo: FakeFolderRepository) async -> FoldersModel {
        let model = FoldersModel(repository: repo)
        await model.activate()
        for _ in 0..<50 where model.folders == nil { await Task.yield() }
        return model
    }

    @Test("«Все» первой и не в списке редактируемых")
    func order() async {
        let model = await loaded(FakeFolderRepository())
        #expect(model.allChats?.title == "Все")
        #expect(model.editable.map(\.id) == ["a", "b"])
        model.deactivate()
    }

    @Test("Перестановка отправляет порядок целиком с «Все» первой, отказ возвращает прежний")
    func move() async {
        let repo = FakeFolderRepository()
        let model = await loaded(repo)
        await model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(repo.reordered == [["all.chat.folder", "b", "a"]])
        #expect(model.editable.map(\.id) == ["b", "a"])
        repo.failWith = .networkUnavailable
        await model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(model.editable.map(\.id) == ["b", "a"])
        #expect(model.errorMessage != nil)
        model.deactivate()
    }

    @Test("Папки по типам создаются только недостающие")
    func typeFolders() async {
        let repo = FakeFolderRepository()
        repo.list.append(ServerFolder(id: "c", title: "Каналы", filters: ["2"]))
        let model = await loaded(repo)
        #expect(model.canAddTypeFolders)
        await model.addTypeFolders()
        #expect(repo.created.map(\.0) == ["Личные", "Боты"])
        #expect(repo.created.map(\.2) == [["4"], ["10"]])
        model.deactivate()
    }

    @Test("Перестановка как в SwiftUI")
    func moving() {
        let items = ["a", "b", "c", "d"]
        #expect(FoldersModel.moving(items, fromOffsets: IndexSet(integer: 0), toOffset: 3) == ["b", "c", "a", "d"])
        #expect(FoldersModel.moving(items, fromOffsets: IndexSet(integer: 3), toOffset: 0) == ["d", "a", "b", "c"])
        #expect(FoldersModel.moving(items, fromOffsets: IndexSet([0, 2]), toOffset: 4) == ["b", "d", "a", "c"])
    }
}

@Suite("Мост мини-приложения")
struct MiniAppBridgeTests {
    private let bridge = MiniAppBridge()
    private let size = CGSize(width: 390, height: 700)

    @Test("Контекст запуска и размер отвечают с requestId")
    func replies() {
        #expect(bridge.handle(event: "WebAppGetLaunchContext", json: #"{"requestId":"r1"}"#, viewport: size)
            == [.reply(event: "WebAppGetLaunchContext", json: #"{"entryPoint":"settings","requestId":"r1"}"#)])
        #expect(bridge.handle(event: "WebAppGetViewportSize", json: nil, viewport: size)
            == [.reply(event: "WebAppGetViewportSize", json: #"{"height":700,"isStateStable":true,"width":390}"#)])
    }

    @Test("Кнопка «Назад», подтверждение закрытия, ссылки")
    func actions() {
        #expect(bridge.handle(event: "WebAppSetupBackButton", json: #"{"isVisible":true}"#, viewport: size) == [.backButton(visible: true)])
        #expect(bridge.handle(event: "WebAppSetupClosingBehavior", json: #"{"needConfirmation":true}"#, viewport: size) == [.closingConfirmation(true)])
        #expect(bridge.handle(event: "WebAppOpenLink", json: #"{"url":"https://max.ru"}"#, viewport: size) == [.openLink(URL(string: "https://max.ru")!)])
        #expect(bridge.handle(event: "WebAppClose", json: nil, viewport: size) == [.close])
    }

    @Test("Неизвестный метод с requestId получает ошибку client.<метод>.unsupported")
    func unsupported() {
        #expect(bridge.handle(event: "WebAppRequestPhone", json: #"{"requestId":"7"}"#, viewport: size)
            == [.reply(event: "WebAppRequestPhone", json: #"{"error":{"code":"client.request_phone.unsupported"},"requestId":"7"}"#)])
        #expect(bridge.handle(event: "WebAppRequestPhone", json: nil, viewport: size) == [.ignore])
        #expect(MiniAppBridge.slug("WebAppBiometryGetInfo") == "biometry_get_info")
    }

    @Test("Биометрия Цифрового ID отвечает локально и помнит токен")
    func biometry() {
        let defaults = UserDefaults(suiteName: "maxly.test.miniapp.\(UUID().uuidString)")!
        let bridge = MiniAppBridge(botId: 8250447, deviceId: "dev1", vault: MiniAppVault(defaults: defaults, key: "v"))
        let size = CGSize(width: 390, height: 700)
        #expect(bridge.handle(event: "WebAppBiometryGetInfo", json: #"{"requestId":"b"}"#, viewport: size)
            == [.reply(event: "WebAppBiometryGetInfo", json: #"{"accessGranted":false,"accessRequested":false,"available":true,"deviceId":"dev1","requestId":"b","tokenSaved":false,"type":["unknown"]}"#)])
        #expect(bridge.handle(event: "WebAppBiometryUpdateToken", json: #"{"token":"t1","requestId":"u"}"#, viewport: size)
            == [.reply(event: "WebAppBiometryUpdateToken", json: #"{"requestId":"u","status":"updated"}"#)])
    }

    @Test("Поделиться собирает текст и ссылку")
    func share() {
        #expect(bridge.handle(event: "WebAppShare", json: #"{"text":"Привет","link":"https://max.ru","requestId":"s"}"#, viewport: size)
            == [.share(text: "Привет\nhttps://max.ru", requestId: "s")])
        #expect(bridge.shareFinished(requestId: "s", completed: true) == .reply(event: "WebAppShare", json: #"{"requestId":"s","status":"shared"}"#))
    }
}
