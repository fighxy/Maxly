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
        case accountLimits

        var id: String {
            switch self {
            case .profileQR: "qr"
            case .invite: "invite"
            case .miniApp(let kind): "app.\(kind.rawValue)"
            case .accountLimits: "limits"
            }
        }
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)

            // Пока ограничения нового сеанса действуют, о них напоминает строка под шапкой.
            if let row = AccountLimitsText().row(container.accountLimits.limits, now: Date()) {
                Section {
                    Button {
                        sheet = .accountLimits
                    } label: {
                        SettingsRowLabel(row.title, systemImage: "timer", tint: .orange, subtitle: row.subtitle)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                SettingsButtonRow(title: "Цифровой ID", systemImage: "person.text.rectangle.fill", tint: .blue) {
                    sheet = .miniApp(.digitalId)
                }
                SettingsButtonRow(title: "Войти в Сферум", systemImage: "graduationcap.fill", tint: .indigo) {
                    sheet = .miniApp(.sferum)
                }
            }

            Section {
                SettingsButtonRow(title: "Пригласить друзей", systemImage: "person.2.fill", tint: .green) {
                    sheet = .invite
                }
            }

            Section {
                NavigationLink {
                    PlaceholderSettingsView(title: "Уведомления и звук", systemImage: "bell.badge")
                } label: {
                    SettingsRowLabel("Уведомления и звук", systemImage: "bell.badge.fill", tint: .red)
                }
                NavigationLink {
                    SecurityView(
                        account: account,
                        model: container.securitySettingsModel(),
                        privacy: container.privacySettingsModel(),
                        ghost: container.ghostSettingsModel(),
                        privateMode: container.privateMode,
                        makeEmailFlow: container.recoveryEmailFlow,
                        makeBotApp: { container.botAppModel($0) }
                    )
                } label: {
                    SettingsRowLabel("Безопасность", systemImage: "lock.shield.fill", tint: .gray)
                }
                NavigationLink {
                    DevicesView(model: container.devicesModel())
                } label: {
                    SettingsRowLabel("Устройства", systemImage: "laptopcomputer.and.iphone", tint: .teal)
                }
                NavigationLink {
                    if let model = container.storageModel() {
                        DataStorageView(model: model)
                    } else {
                        PlaceholderSettingsView(title: "Данные и память", systemImage: "internaldrive")
                    }
                } label: {
                    SettingsRowLabel("Данные и память", systemImage: "internaldrive.fill", tint: .green)
                }
            }

            Section {
                NavigationLink {
                    MessagesSettingsView(model: account) { await container.reactionChoices() }
                } label: {
                    SettingsRowLabel("Сообщения", systemImage: "bubble.left.fill", tint: .green)
                }
                SettingsButtonRow(title: "Избранное", systemImage: "bookmark.fill", tint: .orange) {
                    onOpenChat(Chat.savedMessagesId)
                }
                // Архив своих историй: только когда сервер его включил (`stories-history`).
                if account.settings.storiesHistory, let archive = container.storyArchiveModel() {
                    NavigationLink {
                        StoryArchiveView(model: archive)
                    } label: {
                        SettingsRowLabel("Мои истории", systemImage: "clock.arrow.circlepath", tint: .pink)
                    }
                }
                SettingsButtonRow(title: "Контакты", systemImage: "person.crop.circle.fill", tint: .gray, isWorking: syncingContacts) {
                    guard !syncingContacts else { return }
                    syncingContacts = true
                    Task {
                        await container.syncContacts()
                        syncingContacts = false
                        onOpenContacts()
                    }
                }
                NavigationLink {
                    FoldersView(model: container.foldersModel(), list: list)
                } label: {
                    SettingsRowLabel("Папки", systemImage: "folder.fill", tint: .blue)
                }
                NavigationLink {
                    AppearanceView(settings: container.appearance)
                } label: {
                    SettingsRowLabel("Оформление", systemImage: "textformat.size", tint: .purple)
                }
            }

            Section {
                NavigationLink {
                    AboutView(container: container)
                } label: {
                    SettingsRowLabel("О приложении", systemImage: "info.circle.fill", tint: .gray, badge: AppContainer.versionNumber)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    sheet = .profileQR
                } label: {
                    Image(systemName: "qrcode")
                }
                .accessibilityLabel("QR-код профиля")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EditProfileView(account: account, onLogout: onLogout)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Изменить профиль")
            }
        }
        .task { await account.activate() }
        // Свой статус спрашивается, только пока шапка на экране (docs/privacy.md).
        .onAppear { container.ghostSettingsModel().setScreenVisible(true) }
        .onDisappear {
            account.isPhoneRevealed = false
            container.ghostSettingsModel().setScreenVisible(false)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .profileQR:
                LinkQRSheet(
                    title: "Мой QR-код",
                    caption: "Отсканируйте код камерой, чтобы открыть профиль в MAX",
                    link: profileLink
                )
            case .invite:
                LinkQRSheet(
                    title: "Пригласить друзей",
                    caption: "Отправьте ссылку или покажите QR-код, чтобы друзья нашли вас в MAX",
                    link: account.settings.inviteLink ?? account.profile?.link,
                    shareMessage: "Присоединяйся ко мне в MAX"
                )
            case .miniApp(let kind):
                MiniAppSheet(model: container.miniAppModel(kind))
            case .accountLimits:
                if let limits = container.accountLimits.limits {
                    AccountLimitsSheet(content: AccountLimitsText().content(limits, now: Date()))
                }
            }
        }
        .fullScreenCover(isPresented: $showsViewer) {
            AvatarViewer(account: account) { avatarMenu = true }
        }
        .avatarPicker(isPresented: $avatarMenu, account: account)
        .alert(
            "Не получилось",
            isPresented: Binding(get: { account.errorMessage != nil }, set: { if !$0 { account.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.errorMessage ?? "")
        }
    }

    private var profileLink: URL? {
        account.settings.inviteLink ?? account.profile?.link
    }

    private var header: some View {
        VStack(spacing: 10) {
            Button {
                if account.hasPhoto { showsViewer = true } else { avatarMenu = true }
            } label: {
                ProfileAvatar(account: account, size: 96)
            }
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
                    Button {
                        withAnimation(.snappy) { account.isPhoneRevealed.toggle() }
                    } label: {
                        Image(systemName: account.isPhoneRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(account.isPhoneRevealed ? "Скрыть номер" : "Показать номер")
                }
            }

            // Свой статус глазами сервера: виден, пока «Показывать мой онлайн» включено.
            let ghost = container.ghostSettingsModel()
            if ghost.showsOwnPresence, let presence = ghost.ownPresence, presence != .unknown {
                OwnPresenceLine(model: ghost)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// Редактирование профиля: фото, имя, «О себе», удаление при неактивности, выход и удаление.
struct EditProfileView: View {
    @Bindable var account: AccountSettingsModel
    var onLogout: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var about = ""
    @State private var loaded = false
    @State private var avatarMenu = false
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var typingDelete = false
    @State private var deleteWord = ""
    @State private var deleted = false

    private static let aboutLimit = 400
    private static let deleteKeyword = "УДАЛИТЬ"

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Button { avatarMenu = true } label: {
                        ProfileAvatar(account: account, size: 88)
                    }
                    .buttonStyle(.plain)
                    Button(account.hasPhoto ? "Изменить фото" : "Добавить фото") { avatarMenu = true }
                        .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Имя", text: $firstName)
                    .textContentType(.givenName)
                TextField("Фамилия", text: $lastName)
                    .textContentType(.familyName)
            }

            Section {
                TextField("О себе", text: $about, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: about) { _, text in
                        if text.count > Self.aboutLimit { about = String(text.prefix(Self.aboutLimit)) }
                    }
            } header: {
                Text("О себе")
            } footer: {
                Text("\(about.count) из \(Self.aboutLimit)")
            }

            Section {
                Picker("Удалить профиль при неактивности", selection: Binding(
                    get: { account.settings.inactiveTTL },
                    set: { value in Task { await account.setInactiveTTL(value) } }
                )) {
                    ForEach(InactiveTTL.allCases, id: \.self) { ttl in
                        Text(ttl.title).tag(ttl)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!account.settings.isKnown)
            } footer: {
                Text("Если вы не будете заходить в MAX всё это время, профиль и переписка удалятся.")
            }

            Section {
                Button("Выйти из профиля", role: .destructive) { confirmLogout = true }
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if account.isSaving {
                    ProgressView()
                } else {
                    Button("Готово") {
                        Task {
                            if await account.saveProfile(firstName: firstName, lastName: lastName, about: about) { dismiss() }
                        }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || !hasChanges)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Удалить профиль")
            }
        }
        .onAppear(perform: fill)
        .onChange(of: account.profile) { _, _ in if !loaded { fill() } }
        .avatarPicker(isPresented: $avatarMenu, account: account)
        .confirmationDialog("Выйти из профиля?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive, action: onLogout)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сеанс на этом устройстве завершится, переписка на нём будет удалена.")
        }
        .alert("Удалить профиль?", isPresented: $confirmDelete) {
            Button("Продолжить", role: .destructive) {
                deleteWord = ""
                typingDelete = true
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Профиль будет удалён безвозвратно через 30 дней. Если за это время войти снова, удаление отменится.")
        }
        .alert("Подтвердите удаление", isPresented: $typingDelete) {
            TextField(Self.deleteKeyword, text: $deleteWord)
                .textInputAutocapitalization(.characters)
            Button("Удалить профиль", role: .destructive) {
                guard deleteWord.trimmingCharacters(in: .whitespaces).uppercased() == Self.deleteKeyword else { return }
                Task {
                    if await account.deleteAccount() { deleted = true }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Введите слово «\(Self.deleteKeyword)», чтобы удалить профиль.")
        }
        .alert("Профиль будет удалён", isPresented: $deleted) {
            Button("OK", action: onLogout)
        } message: {
            Text(deletionMessage)
        }
    }

    private var deletionMessage: String {
        let when = account.deletionDate.map { $0.formatted(date: .long, time: .omitted) }
        let head = when.map { "Профиль и переписка удалятся \($0)." } ?? "Через 30 дней профиль и переписка удалятся навсегда."
        return head + " Если войти раньше, удаление отменится. Сейчас вы выйдете из аккаунта."
    }

    private var hasChanges: Bool {
        guard let profile = account.profile else { return true }
        return firstName != profile.firstName || lastName != profile.lastName || about != profile.about
    }

    private func fill() {
        guard let profile = account.profile else { return }
        firstName = profile.firstName
        lastName = profile.lastName
        about = profile.about
        loaded = true
    }
}
