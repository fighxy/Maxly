import Foundation
import Observation
import MaxlyDomain

/// Локальные биометрия и хранилище мини-приложения. Цифровой ID спрашивает их на старте.
/// Ответ «не поддержано» страница показывает как «Техническая заминка».
public final class MiniAppVault: @unchecked Sendable {
    public static let shared = MiniAppVault()

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "maxly.miniAppVault") {
        self.defaults = defaults
        self.key = key
    }

    public struct Biometry: Equatable, Sendable {
        public var accessRequested = false
        public var accessGranted = false
        public var token: String?
    }

    public func biometry(botId: Int64) -> Biometry {
        lock.lock(); defer { lock.unlock() }
        let obj = bot("biometry", botId)
        return Biometry(
            accessRequested: obj?["accessRequested"] as? Bool ?? false,
            accessGranted: obj?["accessGranted"] as? Bool ?? false,
            token: obj?["token"] as? String
        )
    }

    public func saveBiometry(botId: Int64, _ value: Biometry) {
        lock.lock(); defer { lock.unlock() }
        var obj: [String: Any] = [
            "accessRequested": value.accessRequested,
            "accessGranted": value.accessGranted,
        ]
        if let token = value.token, !token.isEmpty { obj["token"] = token }
        putBot("biometry", botId, obj)
    }

    /// Пустая строка — уже сохранённый запасной идентификатор.
    public func deviceId(_ given: String) -> String {
        if !given.isEmpty { return given }
        lock.lock(); defer { lock.unlock() }
        var root = load()
        if let existing = root["deviceId"] as? String, !existing.isEmpty { return existing }
        let created = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        root["deviceId"] = String(created)
        store(root)
        return String(created)
    }

    public func get(space: String, botId: Int64, key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return bot(space, botId)?[key] as? String
    }

    public func put(space: String, botId: Int64, key: String, value: String?) {
        lock.lock(); defer { lock.unlock() }
        var obj = bot(space, botId) ?? [:]
        if let value { obj[key] = value } else { obj.removeValue(forKey: key) }
        putBot(space, botId, obj)
    }

    public func clear(space: String, botId: Int64) {
        lock.lock(); defer { lock.unlock() }
        putBot(space, botId, [:])
    }

    private func bot(_ space: String, _ botId: Int64) -> [String: Any]? {
        let bots = load()[space] as? [String: Any]
        return bots?[String(botId)] as? [String: Any]
    }

    private func putBot(_ space: String, _ botId: Int64, _ value: [String: Any]) {
        var root = load()
        var bots = root[space] as? [String: Any] ?? [:]
        bots[String(botId)] = value
        root[space] = bots
        store(root)
    }

    private func load() -> [String: Any] {
        guard let data = defaults.data(forKey: key),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func store(_ root: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Мост между страницей мини-приложения и приложением.
///
/// Страница вызывает `window.WebViewHandler.postEvent(имя, JSON)`, ответ приходит ей через
/// `window.WebApp.sendEvent(имя, JSON)`. Здесь только разбор запросов и сборка ответов:
/// `WKWebView` и системные действия — в приложении. Список событий в docs/settings.md.
public struct MiniAppBridge: Sendable {
    /// Что сделать приложению в ответ на событие страницы.
    public enum Action: Equatable, Sendable {
        case ready
        case close
        case backButton(visible: Bool)
        case closingConfirmation(Bool)
        case openLink(URL)
        case haptic(Haptic)
        /// Системное «Поделиться»; ответ страница получит через `shareFinished`.
        case share(text: String, requestId: String?)
        /// Ответ странице: событие и JSON.
        case reply(event: String, json: String)
        case ignore
    }

    public enum Haptic: Equatable, Sendable {
        case impact(String)
        case notification(String)
        case selection
    }

    /// Точка входа для `WebAppGetLaunchContext`.
    public let entryPoint: String
    public let botId: Int64
    public let deviceId: String
    private let vault: MiniAppVault

    public init(entryPoint: String = "settings", botId: Int64 = 0, deviceId: String = "", vault: MiniAppVault = .shared) {
        self.entryPoint = entryPoint
        self.botId = botId
        self.deviceId = deviceId
        self.vault = vault
    }

    /// Разбор события страницы. `viewport` — размер листа в точках.
    public func handle(event name: String, json: String?, viewport: CGSize) -> [Action] {
        var data: [String: Any] = [:]
        if let json, !json.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                return []
            }
            data = object
        }
        let requestId = (data["requestId"]).map { "\($0)" }
        switch name {
        case "WebAppReady":
            return [.ready]
        case "WebAppClose":
            return [.close]
        case "WebAppSetupBackButton":
            return [.backButton(visible: data["isVisible"] as? Bool ?? false)]
        case "WebAppSetupClosingBehavior":
            return [.closingConfirmation(data["needConfirmation"] as? Bool ?? false)]
        case "WebAppGetLaunchContext":
            return [reply(name, requestId, ["entryPoint": entryPoint])]
        case "WebAppGetViewportSize":
            return [reply(name, requestId, [
                "width": Int(viewport.width.rounded()),
                "height": Int(viewport.height.rounded()),
                "isStateStable": true,
            ])]
        case "WebAppOpenLink", "WebAppOpenMaxLink":
            guard let text = data["url"] as? String, let url = URL(string: text) else { return [] }
            return [.openLink(url)]
        case "WebAppHapticFeedbackImpact":
            return [.haptic(.impact(data["impactStyle"] as? String ?? "light")), status(name, requestId, "impactOccured")]
        case "WebAppHapticFeedbackNotification":
            return [.haptic(.notification(data["notificationType"] as? String ?? "success")), status(name, requestId, "notificationOccured")]
        case "WebAppHapticFeedbackSelectionChange":
            return [.haptic(.selection), status(name, requestId, "selectionChanged")]
        case "WebAppShare":
            let parts = [data["text"] as? String, data["link"] as? String].compactMap { $0 }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return [failure(name, requestId, "invalid_request")].compactMap { $0 } }
            return [.share(text: parts.joined(separator: "\n"), requestId: requestId)]
        case "WebAppBiometryGetInfo":
            return [biometryInfo(name, requestId)]
        case "WebAppBiometryRequestAccess":
            return [biometryAccess(name, requestId)]
        case "WebAppBiometryRequestAuth":
            return [biometryAuth(name, requestId)]
        case "WebAppBiometryUpdateToken":
            return [biometryUpdate(name, requestId, data)]
        case "WebAppBiometryOpenSettings":
            return [reply(name, requestId, ["status": "opened"])]
        case "WebAppSecureStorageGetKey":
            return [storageGet("secure", name, requestId, data)]
        case "WebAppSecureStorageSaveKey":
            return [storageSave("secure", name, requestId, data)]
        case "WebAppSecureStorageClear":
            return [storageClear("secure", name, requestId)]
        case "WebAppDeviceStorageGetKey":
            return [storageGet("device", name, requestId, data)]
        case "WebAppDeviceStorageSaveKey":
            return [storageSave("device", name, requestId, data)]
        case "WebAppDeviceStorageClear":
            return [storageClear("device", name, requestId)]
        case "WebAppStat", "WebAppUrlInterceptor", "WebAppBackButtonPressed":
            return [.ignore]
        default:
            Log.info(.settings, "Мини-приложение: неподдержанный метод \(name)")
            return [failure(name, requestId, "unsupported") ?? .ignore]
        }
    }

    /// Ответ на `WebAppShare` после системного листа.
    public func shareFinished(requestId: String?, completed: Bool) -> Action {
        reply("WebAppShare", requestId, ["status": completed ? "shared" : "cancelled"])
    }

    /// Нажата системная «Назад», когда страница показала свою кнопку.
    public var backPressed: Action { .reply(event: "WebAppBackButtonPressed", json: "{}") }

    /// `request_phone` из `WebAppRequestPhone`: имя метода без `WebApp` в snake_case.
    public static func slug(_ method: String) -> String {
        let name = method.hasPrefix("WebApp") ? String(method.dropFirst(6)) : method
        var out = ""
        for (index, char) in name.enumerated() {
            if char.isUppercase, index > 0 { out.append("_") }
            out.append(char.lowercased())
        }
        return out.isEmpty ? "unsupported_method" : out
    }

    private func biometryInfo(_ name: String, _ requestId: String?) -> Action {
        reply(name, requestId, infoFields(vault.biometry(botId: botId)))
    }

    private func biometryAccess(_ name: String, _ requestId: String?) -> Action {
        var next = vault.biometry(botId: botId)
        next.accessRequested = true
        next.accessGranted = true
        vault.saveBiometry(botId: botId, next)
        return reply(name, requestId, infoFields(next))
    }

    private func biometryAuth(_ name: String, _ requestId: String?) -> Action {
        var current = vault.biometry(botId: botId)
        let token = current.token.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        current.accessRequested = true
        current.accessGranted = true
        current.token = token
        vault.saveBiometry(botId: botId, current)
        return reply(name, requestId, ["token": token, "status": "authorized", "granted": true, "accessGranted": true])
    }

    private func biometryUpdate(_ name: String, _ requestId: String?, _ data: [String: Any]) -> Action {
        let token: String?
        if data["token"] is NSNull || data["token"] == nil {
            token = nil
        } else {
            token = data["token"] as? String
        }
        if let token, token.count > 1024 { return failure(name, requestId, "too_large") ?? .ignore }
        var current = vault.biometry(botId: botId)
        if token == nil || token?.isEmpty == true {
            current.token = nil
            vault.saveBiometry(botId: botId, current)
            return reply(name, requestId, ["status": "removed"])
        }
        current.accessRequested = true
        current.accessGranted = true
        current.token = token
        vault.saveBiometry(botId: botId, current)
        return reply(name, requestId, ["status": "updated"])
    }

    private func infoFields(_ bio: MiniAppVault.Biometry) -> [String: Any] {
        [
            "available": true,
            "accessRequested": bio.accessRequested,
            "accessGranted": bio.accessGranted,
            "tokenSaved": !(bio.token ?? "").isEmpty,
            "deviceId": vault.deviceId(deviceId),
            "type": ["unknown"],
        ]
    }

    private func storageGet(_ space: String, _ name: String, _ requestId: String?, _ data: [String: Any]) -> Action {
        guard let key = data["key"] as? String, !key.isEmpty else { return failure(name, requestId, "invalid_request") ?? .ignore }
        guard let value = vault.get(space: space, botId: botId, key: key) else { return failure(name, requestId, "not_found") ?? .ignore }
        return reply(name, requestId, ["key": key, "value": value])
    }

    private func storageSave(_ space: String, _ name: String, _ requestId: String?, _ data: [String: Any]) -> Action {
        guard let key = data["key"] as? String, !key.isEmpty else { return failure(name, requestId, "invalid_request") ?? .ignore }
        if key.count > 128 { return failure(name, requestId, "too_large_key") ?? .ignore }
        if data["value"] is NSNull || data["value"] == nil {
            vault.put(space: space, botId: botId, key: key, value: nil)
            return reply(name, requestId, ["status": "saved"])
        }
        guard let value = data["value"] as? String else { return failure(name, requestId, "invalid_request") ?? .ignore }
        if value.count > 8192 { return failure(name, requestId, "too_large_value") ?? .ignore }
        vault.put(space: space, botId: botId, key: key, value: value)
        return reply(name, requestId, ["status": "saved"])
    }

    private func storageClear(_ space: String, _ name: String, _ requestId: String?) -> Action {
        vault.clear(space: space, botId: botId)
        return reply(name, requestId, ["status": "cleared"])
    }

    private func status(_ name: String, _ requestId: String?, _ value: String) -> Action {
        reply(name, requestId, ["status": value])
    }

    private func failure(_ name: String, _ requestId: String?, _ reason: String) -> Action? {
        guard let requestId else { return nil }
        return reply(name, requestId, ["error": ["code": "client.\(Self.slug(name)).\(reason)"]])
    }

    private func reply(_ name: String, _ requestId: String?, _ fields: [String: Any]) -> Action {
        var body = fields
        if let requestId { body["requestId"] = requestId }
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .reply(event: name, json: String(decoding: data, as: UTF8.self))
    }
}

/// Лист мини-приложения: запуск, перезапуск после внешнего шага. Приложение из настроек
/// (Цифровой ID, Сферум) или бота: кнопка «Открыть приложение» в чате, inline-кнопка `OPEN_APP`.
@MainActor
@Observable
public final class MiniAppModel {
    public enum State: Equatable, Sendable {
        case loading
        case ready(MiniApp)
        case failed(String)
    }

    /// Приложение настроек; `nil` у приложения бота.
    public let kind: MiniApp.Kind?
    public let title: String
    public private(set) var state: State = .loading
    public var closingNeedsConfirmation = false
    public var showsBackButton = false

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let start: () async throws(MaxlyError) -> MiniApp

    public init(kind: MiniApp.Kind, repository: any AccountRepository) {
        self.kind = kind
        self.title = kind.title
        self.repository = repository
        self.start = { () async throws(MaxlyError) -> MiniApp in try await repository.launchMiniApp(kind) }
    }

    /// Мини-приложение бота: `start` спрашивает у сервера адрес запуска (`WEB_APP_INIT_DATA`).
    public init(title: String, repository: any AccountRepository, start: @escaping () async throws(MaxlyError) -> MiniApp) {
        self.kind = nil
        self.title = title
        self.repository = repository
        self.start = start
    }

    public func launch() async {
        state = .loading
        do {
            let app = try await start()
            Log.info(.settings, "Мини-приложение \(kind?.rawValue ?? title): бот \(app.botId)")
            state = .ready(app)
        } catch {
            state = .failed(error.message)
        }
    }

    /// Возврат с внешнего шага: сервер даёт новый запуск, лист открывает его.
    public func handleCallback(_ url: URL) async {
        state = .loading
        do {
            state = .ready(try await repository.miniAppCallback(url: url))
            Log.info(.settings, "Мини-приложение \(kind?.rawValue ?? title): возврат с внешнего шага")
        } catch {
            state = .failed(error.message)
        }
    }
}
