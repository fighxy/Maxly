import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Вкладка «Настройки»: шапка профиля и разделы, как в iOS-версии Komet (docs/settings.md).
///
/// Поиска и кнопки «×» нет: это вкладка. Стекло только у кнопок панели навигации.
/// Крупного заголовка сверху нет: вкладка и так подписана.
struct SettingsView: View {
    @Bindable var container: AppContainer
    @Bindable var account: AccountSettingsModel
    @Bindable var list: ChatListViewModel
    var onOpenChat: (String) -> Void
    var onOpenContacts: () -> Void
    var onLogout: () -> Void

    @State private var sheet: SettingsSheet?
    @State private var avatarMenu = false
    @State private var showsViewer = false
    @State private var syncingContacts = false

    enum SettingsSheet: Identifiable {
        case profileQR
        case invite
        case miniApp(MiniApp.Kind)

        var id: String {
            switch self {
            case .profileQR: "qr"
            case .invite: "invite"
            case .miniApp(let kind): "app.\(kind.rawValue)"
            }
        }
    }

    var body: some View {
        List {
            Section { header }
            .listRowBackground(Color.clear)
            Section {
                SettingsButtonRow(title: "Цифровой ID", systemImage: "person.text.rectangle.fill", tint: .blue) { sheet = .miniApp(.digitalId) }
                SettingsButtonRow(title: "Войти в Сферум", systemImage: "graduationcap.fill", tint: .indigo) { sheet = .miniApp(.sferum) }
            }
            Section {
                SettingsButtonRow(title: "Пригласить друзей", systemImage: "person.2.fill", tint: .green) { sheet = .invite }
            }
            Section {
                NavigationLink { PlaceholderSettingsView(title: "Уведомления и звук", systemImage: "bell.badge") } label: {
                    SettingsRowLabel("Уведомления и звук", systemImage: "bell.badge.fill", tint: .red)
                }
                NavigationLink {
                    SecurityView(account: account, model: container.securitySettingsModel(), privateMode: container.privateMode, makeEmailFlow: container.recoveryEmailFlow)
                } label: {
                    SettingsRowLabel("Безопасность", systemImage: "lock.shield.fill", tint: .gray)
                }
                NavigationLink { DevicesView(model: container.devicesModel()) } label: {
                    SettingsRowLabel("Устройства", systemImage: "laptopcomputer.and.iphone", tint: .teal)
                }
                NavigationLink {
                    if let model = container.storageModel() { DataStorageView(model: model) } else { PlaceholderSettingsView(title: "Данные и память", systemImage: "internaldrive") }
                } label: {
                    SettingsRowLabel("Данные и память", systemImage: "internaldrive.fill", tint: .green)
                }
            }
            Section {
                NavigationLink { PlaceholderSettingsView(title: "Сообщения", systemImage: "bubble.left.and.text.bubble.right") } label: {
                    SettingsRowLabel("Сообщения", systemImage: "bubble.left.fill", tint: .green)
                }
                SettingsButtonRow(title: "Избранное", systemImage: "bookmark.fill", tint: .orange) { onOpenChat(Chat.savedMessagesId) }
                SettingsButtonRow(title: "Контакты", systemImage: "person.crop.circle.fill", tint: .gray, isWorking: syncingContacts) {
                    guard !syncingContacts else { return }
                    syncingContacts = true
                    Task { await container.syncContacts(); syncingContacts = false; onOpenContacts() }
                }
                NavigationLink { FoldersView(model: container.foldersModel(), list: list) } label: {
                    SettingsRowLabel("Папки", systemImage: "folder.fill", tint: .blue)
                }
                NavigationLink { AppearanceView(settings: container.appearance) } label: {
                    SettingsRowLabel("Оформление", systemImage: "textformat.size", tint: .purple)
                }
            }
            Section {
                NavigationLink { AboutView(container: container) } label: {
                    SettingsRowLabel("О приложении", systemImage: "info.circle.fill", tint: .gray, badge: AppContainer.versionNumber)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { sheet = .profileQR } label: { Image(systemName: "qrcode") }
                .accessibilityLabel("QR-код профиля")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { EditProfileView(account: account, onLogout: onLogout) } label: { Image(systemName: "pencil") }
                .accessibilityLabel("Изменить профиль")
            }
        }
        .task { await account.activate() }
        .onDisappear { account.isPhoneRevealed = false }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .profileQR:
                LinkQRSheet(title: "Мой QR-код", caption: "Отсканируйте код камерой, чтобы открыть профиль в MAX", link: profileLink)
            case .invite:
                LinkQRSheet(title: "Пригласить друзей", caption: "Отправьте ссылку или покажите QR-код, чтобы друзья нашли вас в MAX", link: account.settings.inviteLink ?? account.profile?.link, shareMessage: "Присоединяйся ко мне в MAX")
            case .miniApp(let kind):
                MiniAppSheet(model: container.miniAppModel(kind))
            }
        }
        .fullScreenCover(isPresented: $showsViewer) { AvatarViewer(account: account) { avatarMenu = true } }
        .avatarPicker(isPresented: $avatarMenu, account: account)
        .alert("Не получилось", isPresented: Binding(get: { account.errorMessage != nil }, set: { if !$0 { account.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(account.errorMessage ?? "") }
    }

    private var profileLink: URL? { account.settings.inviteLink ?? account.profile?.link }

    private var header: some View {
        VStack(spacing: 10) {
            Button { if account.hasPhoto { showsViewer = true } else { avatarMenu = true } } label: { ProfileAvatar(account: account, size: 96) }
                .buttonStyle(.plain)
                .accessibilityLabel(account.hasPhoto ? "Открыть фото профиля" : "Добавить фото профиля")
            Text(account.profile?.displayName ?? " ")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .redacted(reason: account.profile == nil ? .placeholder : [])
            if !account.headerPhone.isEmpty {
                HStack(spacing: 6) {
                    Text(account.headerPhone)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .privacySensitive()
                        .accessibilityLabel(account.isPhoneRevealed ? account.headerPhone : "Номер скрыт")
                    Button { withAnimation(.snappy) { account.isPhoneRevealed.toggle() } } label: {
                        Image(systemName: account.isPhoneRevealed ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(account.isPhoneRevealed ? "Скрыть номер" : "Показать номер")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
