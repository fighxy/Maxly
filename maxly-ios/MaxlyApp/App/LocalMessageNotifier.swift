import Foundation
import UserNotifications
import MaxlyDomain
import MaxlyPresentation

/// Уведомления о новых сообщениях, пока приложение в фоне (`docs/background.md`).
///
/// Сервер Max шлёт пуши только своему приложению, поэтому уведомление собирается на телефоне:
/// пока `BackgroundKeepAlive` держит приложение живым, сообщения приходят по соединению ядра,
/// и каждое новое чужое сообщение показывается локальным уведомлением. Что показывать —
/// `MessageNotificationRules`. Нажатие открывает чат.
@MainActor
final class LocalMessageNotifier: NSObject, IncomingMessageSink, UNUserNotificationCenterDelegate {
    private var appActive = true
    private let enabled: @MainActor () -> Bool
    /// Нажали на уведомление: открыть этот чат.
    var onOpenChat: ((String) -> Void)?

    init(enabled: @escaping @MainActor () -> Bool) {
        self.enabled = enabled
        super.init()
    }

    /// Приложение на экране: уведомления не нужны, показанные убираются.
    func setAppActive(_ active: Bool) {
        appActive = active
        if active { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
    }

    /// Разрешение на уведомления. Система спрашивает один раз; потом вызов только сообщает,
    /// что выбрал человек, поэтому его можно делать при каждом уходе в фон.
    private var askedPermission = false

    func requestPermissionIfNeeded() async {
        guard !askedPermission else { return }
        askedPermission = true
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        Log.info(.app, "Уведомления: \(granted ? "разрешены" : "запрещены")")
    }

    func incoming(_ notice: IncomingMessageNotice) async {
        guard let content = MessageNotificationRules.content(for: notice, appActive: appActive, enabled: enabled()) else { return }
        let payload = UNMutableNotificationContent()
        payload.title = content.title
        if let subtitle = content.subtitle { payload.subtitle = subtitle }
        payload.body = content.body
        payload.sound = .default
        payload.threadIdentifier = notice.chatId
        payload.userInfo = [Self.chatKey: notice.chatId]
        let request = UNNotificationRequest(identifier: "message-\(notice.chatId)-\(notice.messageId)", content: payload, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            DiagnosticEvent.event("notification.post", ["kind": "message", "result": "ok"])
        } catch {
            Log.warning(.app, "Уведомление не показано: \(error)")
            DiagnosticEvent.event("notification.post", ["kind": "message", "result": "failed"])
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let chatId = response.notification.request.content.userInfo[Self.chatKey] as? String
        completionHandler()
        guard let chatId else { return }
        Task { @MainActor [weak self] in
            DiagnosticEvent.event("notification.action", ["action": "open", "kind": "message"])
            self?.onOpenChat?(chatId)
        }
    }

    /// На экране уведомление о сообщении не показывается: его и так видно.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    private nonisolated static let chatKey = "chatId"
}
