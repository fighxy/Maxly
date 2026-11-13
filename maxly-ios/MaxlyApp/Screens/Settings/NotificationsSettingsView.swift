import SwiftUI
import UIKit
import UserNotifications
import MaxlyPresentation
import MaxlyUI

/// «Уведомления и звук»: звонки и сообщения в свёрнутом приложении (`docs/background.md`) и
/// звуки открытого приложения (`InAppSound`).
struct NotificationsSettingsView: View {
    @Bindable var container: AppContainer
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var denied = false
    @AppStorage(InAppSoundSettings.sentKey) private var sentSound = true
    @AppStorage(InAppSoundSettings.incomingKey) private var incomingSound = true

    var body: some View {
        List {
            Section {
                Toggle("Отправка сообщения", isOn: $sentSound)
                Toggle("Новое сообщение", isOn: $incomingSound)
            } header: {
                Text("Звуки в приложении")
            } footer: {
                Text("Короткий звук, когда вы отправляете сообщение и когда приходит новое, пока Maxly открыт. Чаты без звука молчат. Звуки следуют переключателю «Звонок/Бесшумно» и не звучат во время звонка.")
            }
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
