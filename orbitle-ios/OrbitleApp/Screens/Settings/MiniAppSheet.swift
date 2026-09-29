import SwiftUI
import UIKit
import WebKit
import OrbitleDomain
import OrbitlePresentation

/// Лист мини-приложения MAX (Цифровой ID, Сферум): `WKWebView` с мостом страницы.
struct MiniAppSheet: View {
    /// Модель живёт, пока открыт лист: каждое открытие — новый запуск мини-приложения.
    @State private var model: MiniAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var controller = MiniAppWebController()
    @State private var confirmClose = false

    init(model: @autoclosure () -> MiniAppModel) {
        _model = State(initialValue: model())
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if model.showsBackButton {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                controller.pressBack()
                            } label: {
                                Label("Назад", systemImage: "chevron.backward")
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Закрыть", action: close)
                    }
                }
        }
        .interactiveDismissDisabled(model.closingNeedsConfirmation)
        .task { if case .loading = model.state { await model.launch() } }
        .confirmationDialog("Закрыть «\(model.title)»?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Закрыть", role: .destructive) { dismiss() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Несохранённые данные могут пропасть.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось открыть", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") { Task { await model.launch() } }
                    .buttonStyle(.borderedProminent)
            }
        case .ready(let app):
            MiniAppWebView(app: app, model: model, controller: controller) { dismiss() }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func close() {
        if model.closingNeedsConfirmation { confirmClose = true } else { dismiss() }
    }
}

/// Связь панели навигации листа с открытой страницей: «Назад» уходит в мост.
@MainActor
final class MiniAppWebController {
    weak var webView: WKWebView?
    let bridge = MiniAppBridge(entryPoint: "settings")

    func pressBack() {
        perform(bridge.backPressed)
    }

    /// Ответ странице через `window.WebApp.sendEvent(имя, JSON)`; до готовности SDK — в очередь.
    func deliver(event: String, json: String) {
        guard let webView else { return }
        let script = "window.__orbitleDeliver && window.__orbitleDeliver(\(Self.literal(event)), \(Self.literal(json)));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func perform(_ action: MiniAppBridge.Action) {
        if case .reply(let event, let json) = action { deliver(event: event, json: json) }
    }

    /// Строка Swift как литерал JavaScript.
    static func literal(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text), let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }

    /// Скрипт до загрузки страницы: `window.WebViewHandler.postEvent` отдаёт события приложению,
    /// `__orbitleDeliver` держит ответы, пока страница не поднимет `window.WebApp`.
    static let userScript = """
    (function () {
      if (window.__orbitleBridgeReady) { return; }
      window.__orbitleBridgeReady = true;
      var outbox = [];
      function drain() {
        var target = window.WebApp;
        if (!target || typeof target.sendEvent !== 'function') { return; }
        while (outbox.length > 0) {
          var next = outbox.shift();
          try { target.sendEvent(next.name, next.data); } catch (e) {}
        }
      }
      setInterval(drain, 50);
      window.__orbitleDeliver = function (name, data) { outbox.push({ name: name, data: data }); drain(); };
      function post(name, data) {
        var body = data;
        if (body !== undefined && body !== null && typeof body !== 'string') {
          try { body = JSON.stringify(body); } catch (e) { body = null; }
        }
        try {
          window.webkit.messageHandlers.orbitleWebApp.postMessage({ name: String(name), data: body === undefined ? null : body });
        } catch (e) {}
      }
      window.WebViewHandler = { postEvent: post, resolveShare: function () {} };
    })();
    """
}

/// `WKWebView` мини-приложения. У SwiftUI своего веб-вида нет.
struct MiniAppWebView: UIViewRepresentable {
    let app: MiniApp
    let model: MiniAppModel
    let controller: MiniAppWebController
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, controller: controller, onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: MiniAppWebController.userScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        content.add(WeakScriptHandler(context.coordinator), name: "orbitleWebApp")
        configuration.userContentController = content
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        controller.webView = webView
        context.coordinator.loadedURL = app.url
        webView.load(URLRequest(url: app.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
        // Новый запуск после внешнего шага (Госуслуги): тот же вид, новый адрес.
        if context.coordinator.loadedURL != app.url {
            context.coordinator.loadedURL = app.url
            webView.load(URLRequest(url: app.url))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "orbitleWebApp")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: MiniAppModel
        let controller: MiniAppWebController
        let onClose: () -> Void
        var loadedURL: URL?

        init(model: MiniAppModel, controller: MiniAppWebController, onClose: @escaping () -> Void) {
            self.model = model
            self.controller = controller
            self.onClose = onClose
        }

        func receive(name: String, json: String?) {
            let size = controller.webView?.bounds.size ?? .zero
            for action in controller.bridge.handle(event: name, json: json, viewport: size) {
                switch action {
                case .ready, .ignore:
                    break
                case .close:
                    onClose()
                case .backButton(let visible):
                    model.showsBackButton = visible
                case .closingConfirmation(let needed):
                    model.closingNeedsConfirmation = needed
                case .openLink(let url):
                    UIApplication.shared.open(url)
                case .haptic(let haptic):
                    Self.play(haptic)
                case .share(let text, let requestId):
                    share(text, requestId: requestId)
                case .reply(let event, let json):
                    controller.deliver(event: event, json: json)
                }
            }
        }

        private func share(_ text: String, requestId: String?) {
            guard let presenter = controller.webView?.window?.rootViewController?.topmostPresented else { return }
            let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = controller.webView
            sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                guard let self else { return }
                self.controller.perform(self.controller.bridge.shareFinished(requestId: requestId, completed: completed))
            }
            presenter.present(sheet, animated: true)
        }

        private static func play(_ haptic: MiniAppBridge.Haptic) {
            switch haptic {
            case .impact(let style):
                let value: UIImpactFeedbackGenerator.FeedbackStyle = switch style {
                case "medium": .medium
                case "heavy": .heavy
                case "rigid": .rigid
                case "soft": .soft
                default: .light
                }
                UIImpactFeedbackGenerator(style: value).impactOccurred()
            case .notification(let type):
                let value: UINotificationFeedbackGenerator.FeedbackType = switch type {
                case "error": .error
                case "warning": .warning
                default: .success
                }
                UINotificationFeedbackGenerator().notificationOccurred(value)
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            if MiniApp.isExternalCallback(url) {
                // Возврат с Госуслуг: сервер выдаёт новый запуск, страница открывается заново.
                let model = model
                Task { await model.handleCallback(url) }
                return .cancel
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if !["http", "https", "about", "data", "blob"].contains(scheme) {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }

        // MARK: WKUIDelegate

        /// Ссылки `target=_blank` открываются в том же виде.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

/// `WKUserContentController` держит обработчик сильно: без прослойки координатор не освободится.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: MiniAppWebView.Coordinator?

    init(_ target: MiniAppWebView.Coordinator) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let name = body["name"] as? String else { return }
        let json = body["data"] as? String
        MainActor.assumeIsolated {
            target?.receive(name: name, json: json)
        }
    }
}

private extension UIViewController {
    var topmostPresented: UIViewController {
        var top = self
        while let next = top.presentedViewController { top = next }
        return top
    }
}
