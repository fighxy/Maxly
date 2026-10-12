import SwiftUI
import UIKit
import UserNotifications
import MaxlyUI

/// «Уведомления и звук»: звонки и сообщения в свёрнутом приложении (`docs/background.md`).
struct NotificationsSettingsView: View {
    @Bindable var container: AppContainer
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var denied = false

    var body: some View {
        List {
            Section {
                Toggle("Звонки и сообщения в фоне", isOn: Binding(
                    get: { container.keepsAliveInBackground },
                    set: { container.setKeepsAliveInBackground($0) }
                ))
            } footer: {
                Text("Свёрнутый Maxly остаётся на связи: входящий звонок показывается как обычный звонок iPhone, о новых сообщениях приходят уведомления. Сервер Max шлёт пуши только своему приложению, поэтому Maxly держит соединение сам — это немного расходует батарею. Не работает, если смахнуть Maxly из переключателя приложений или перезагрузить телефон.")
            }
            if denied && container.keepsAliveInBackground {
                Section {
                    Button("Открыть настройки iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Уведомления о сообщениях запрещены в настройках iOS. Звонки приходят и без них.")
                }
            }
        }
        .navigationTitle("Уведомления и звук")
        .navigationBarTitleDisplayMode(.inline)
        // Разрешение могли поменять в настройках iOS, пока экран был открыт.
        .task(id: scenePhase) { denied = await Self.notificationsDenied() }
        .task(id: container.keepsAliveInBackground) { denied = await Self.notificationsDenied() }
    }

    /// Запрещены ли уведомления. Настройки читаются вне главного актора: наружу — только ответ.
    private nonisolated static func notificationsDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
