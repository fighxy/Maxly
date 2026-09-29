import Foundation
import Observation
import OrbitleDomain

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

    public init(entryPoint: String = "settings") {
        self.entryPoint = entryPoint
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

/// Лист мини-приложения: запуск, перезапуск после внешнего шага.
@MainActor
@Observable
public final class MiniAppModel {
    public enum State: Equatable, Sendable {
        case loading
        case ready(MiniApp)
        case failed(String)
    }

    public let kind: MiniApp.Kind
    public private(set) var state: State = .loading
    public var closingNeedsConfirmation = false
    public var showsBackButton = false

    @ObservationIgnored private let repository: any AccountRepository

    public init(kind: MiniApp.Kind, repository: any AccountRepository) {
        self.kind = kind
        self.repository = repository
    }

    public var title: String { kind.title }

    public func launch() async {
        state = .loading
        do {
            let app = try await repository.launchMiniApp(kind)
            Log.info(.settings, "Мини-приложение \(kind.rawValue): бот \(app.botId)")
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
            Log.info(.settings, "Мини-приложение \(kind.rawValue): возврат с внешнего шага")
        } catch {
            state = .failed(error.message)
        }
    }
}
