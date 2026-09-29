import SwiftUI
import OrbitlePresentation
import OrbitleUI

/// Настройки: профиль, вид списка чатов, журнал для отладки и выход.
struct SettingsView: View {
    @Bindable var container: AppContainer
    @Bindable var list: ChatListViewModel
    var onLogout: () -> Void
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(title: "Я", id: container.currentUserId, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Мой профиль")
                            .font(.title3.weight(.semibold))
                        if !container.currentUserId.isEmpty {
                            Text("ID \(container.currentUserId)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            Section {
                Toggle(isOn: Binding(
                    get: { list.usesLocalFilters },
                    set: { container.setLocalFilters($0) }
                )) {
                    Label("Папки по типам чатов", systemImage: "folder")
                }
            } header: {
                Text("Список чатов")
            } footer: {
                Text("Над списком появятся вкладки «Личные», «Группы», «Каналы», «Боты» и «Непрочитанные». Серверные папки, если они есть, показываются вместо них.")
            }
            LogSettingsSection(container: container)
            Section {
                Button("Выйти", role: .destructive) { confirmLogout = true }
            }
            Section {
                HStack(spacing: 14) {
                    OrbitleLogoTile(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Orbitle")
                            .font(.headline)
                        Text(AppContainer.appVersion.replacingOccurrences(of: "Orbitle ", with: "Версия "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            } header: {
                Text("О приложении")
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive, action: onLogout)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Переписка на этом устройстве будет удалена.")
        }
    }
}
