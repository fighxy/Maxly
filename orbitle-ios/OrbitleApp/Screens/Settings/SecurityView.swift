import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Безопасность»: пароль и почта, семейная защита, безопасный режим, конфиденциальность,
/// чёрный список. Настройки конфига меняются сразу и откатываются при отказе сервера.
/// Приватный режим — локальная настройка устройства, сервер о нём не знает.
struct SecurityView: View {
    @Bindable var account: AccountSettingsModel
    @Bindable var model: SecuritySettingsModel
    @Bindable var privateMode: PrivateModeSettings
    let makeEmailFlow: @MainActor () -> RecoveryEmailFlow
    @State private var emailFlow: RecoveryEmailFlow?
    @State private var confirmHideOnline = false

    var body: some View {
        List {
            passwordSection

            Section {
                LabeledContent {
                    SoonBadge()
                } label: {
                    SettingsRowLabel("Семейная защита", systemImage: "figure.and.child.holdinghands", tint: .pink)
                }
            } footer: {
                Text("Мини-приложение семейной защиты ещё не открыто для сторонних клиентов MAX.")
            }

            Section {
                if account.settings.isKnown {
                    Toggle(isOn: Binding(
                        get: { account.settings.safeMode },
                        set: { value in Task { await account.setSafeMode(value) } }
                    )) {
                        SettingsRowLabel("Безопасный режим", systemImage: "checkmark.shield.fill", tint: .green)
                    }
                } else {
                    LabeledContent {
                        ProgressView()
                    } label: {
                        SettingsRowLabel("Безопасный режим", systemImage: "checkmark.shield.fill", tint: .green)
                    }
                }
            } footer: {
                Text("Никто не найдёт вас по номеру, не позвонит и не пригласит в чаты, кроме ваших контактов. Показывается только безопасный контент.")
            }

            Section {
                Picker("Кто видит статус «в сети»", selection: Binding(
                    get: { account.settings.onlineHidden },
                    set: { hidden in
                        if hidden { confirmHideOnline = true } else { Task { await account.setOnlineHidden(false) } }
                    }
                )) {
                    Text(PrivacyAccess.contacts.title).tag(false)
                    Text(PrivacyAccess.nobody.title).tag(true)
                }
                Picker("Кто видит мой номер", selection: Binding(
                    get: { account.settings.phonePrivacy },
                    set: { value in Task { await account.setPhonePrivacy(value) } }
                )) {
                    ForEach(PrivacyAccess.allCases, id: \.self) { access in
                        Text(access.title).tag(access)
                    }
                }
            } header: {
                Text("Конфиденциальность")
            }
            .pickerStyle(.menu)
            .disabled(!account.settings.isKnown)

            privateModeSection

            Section {
                NavigationLink {
                    BlockedUsersView(model: model)
                } label: {
                    SettingsRowLabel("Чёрный список", systemImage: "hand.raised.fill", tint: .red)
                }
            }
        }
        .navigationTitle("Безопасность")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadTwoFactor() }
        .refreshable { await model.loadTwoFactor() }
        .confirmationDialog("Скрыть статус «в сети»?", isPresented: $confirmHideOnline, titleVisibility: .visible) {
            Button("Скрыть от всех") { Task { await account.setOnlineHidden(true) } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы тоже перестанете видеть, кто в сети.")
        }
        .sheet(isPresented: Binding(get: { emailFlow != nil }, set: { if !$0 { emailFlow = nil } })) {
            if let emailFlow {
                RecoveryEmailView(flow: emailFlow) { status in model.apply(status) }
            }
        }
        .alert(
            "Не получилось",
            isPresented: Binding(
                get: { account.errorMessage != nil || model.errorMessage != nil },
                set: { if !$0 { account.errorMessage = nil; model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.errorMessage ?? model.errorMessage ?? "")
        }
    }

    /// Приватный режим: скрывает названия чатов, аватары и тексты на этом устройстве.
    private var privateModeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { privateMode.isEnabled },
                set: { privateMode.setEnabled($0) }
            )) {
                SettingsRowLabel("Приватный режим", systemImage: "eye.slash.fill", tint: .indigo)
            }
            if privateMode.isEnabled {
                Picker("Вид", selection: Binding(
                    get: { privateMode.style },
                    set: { privateMode.setStyle($0) }
                )) {
                    ForEach(PrivateModeStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
            Toggle("Кнопка в списке чатов", isOn: Binding(
                get: { privateMode.showsQuickToggle },
                set: { privateMode.setShowsQuickToggle($0) }
            ))
        } footer: {
            Text(privateModeFooter)
        }
    }

    private var privateModeFooter: String {
        let base = "Названия чатов, аватары и сообщения скрываются от чужих глаз. Нажмите на сообщение, чтобы посмотреть его на 15 секунд. Действует только на этом устройстве, уведомления не меняются."
        guard privateMode.isEnabled else { return base }
        switch privateMode.style {
        case .placeholder: return base + " Заглушки заменяют текст на «Вы получили сообщение»."
        case .blur: return base + " Размытие оставляет видимыми длину и форму текста."
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        Section {
            LabeledContent {
                switch model.twoFactor {
                case .loading: ProgressView()
                case .loaded(let status): Text(status.isEnabled ? "Включён" : "Выключен")
                case .failed: Text("Неизвестно")
                }
            } label: {
                SettingsRowLabel("Пароль для входа", systemImage: "key.fill", tint: .orange)
            }
            if let status = model.twoFactor.value, status.isEnabled {
                if let masked = model.maskedEmail {
                    LabeledContent("Почта для восстановления", value: masked)
                    Button("Изменить почту") { emailFlow = makeEmailFlow() }
                } else {
                    Button("Укажите почту для восстановления") { emailFlow = makeEmailFlow() }
                }
            }
        } footer: {
            switch model.twoFactor {
            case .loaded(let status) where !status.isEnabled:
                Text("Пароль защищает вход с нового устройства. Включить его можно будет здесь — скоро.")
            case .loaded:
                Text("Почта нужна, чтобы восстановить доступ, если вы забудете пароль.")
            case .failed(let message):
                Text(message)
            case .loading:
                EmptyView()
            }
        }
    }
}

/// Смена почты для восстановления: пароль → почта → код из письма.
struct RecoveryEmailView: View {
    @Bindable var flow: RecoveryEmailFlow
    let onDone: (TwoFactorStatus) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                switch flow.step {
                case .password:
                    Section {
                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                            .focused($focused)
                            .onSubmit { Task { await flow.submitPassword(password) } }
                    } footer: {
                        Text("Введите текущий пароль для входа.")
                    }
                case .email:
                    Section {
                        TextField("Почта", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .onSubmit { Task { await flow.submitEmail(email) } }
                    } footer: {
                        Text("На неё придёт код подтверждения.")
                    }
                case .code(let address):
                    Section {
                        TextField("Код из письма", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focused)
                    } footer: {
                        Text("Код отправлен на \(address).")
                    }
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Button(resendTitle) { Task { await flow.resendCode() } }
                                .disabled(!flow.canResend || flow.isWorking)
                        }
                        Button("Изменить адрес") { flow.editEmail() }
                    }
                case .done:
                    Section {
                        Label("Почта для восстановления сохранена", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let error = flow.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Почта для восстановления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if flow.isWorking {
                        ProgressView()
                    } else {
                        Button(primaryTitle, action: primary)
                            .disabled(!canSubmit)
                    }
                }
            }
            .onAppear { focused = true }
            .onChange(of: flow.step) { _, step in
                if case .done(let status) = step {
                    onDone(status)
                    dismiss()
                }
                focused = true
            }
        }
    }

    private var resendTitle: String {
        guard !flow.canResend, let at = flow.resendAvailableAt else { return "Отправить код ещё раз" }
        let seconds = max(0, Int(at.timeIntervalSinceNow.rounded(.up)))
        return "Отправить ещё раз через \(seconds) с"
    }

    private var primaryTitle: String {
        switch flow.step {
        case .password: "Далее"
        case .email: "Получить код"
        case .code, .done: "Готово"
        }
    }

    private var canSubmit: Bool {
        switch flow.step {
        case .password: !password.isEmpty
        case .email: !email.isEmpty
        case .code: !code.filter(\.isNumber).isEmpty
        case .done: true
        }
    }

    private func primary() {
        Task {
            switch flow.step {
            case .password: await flow.submitPassword(password)
            case .email: await flow.submitEmail(email)
            case .code: await flow.submitCode(code)
            case .done: dismiss()
            }
        }
    }
}

/// Чёрный список: заблокированные пользователи с «Разблокировать».
struct BlockedUsersView: View {
    @Bindable var model: SecuritySettingsModel
    @State private var pending: BlockedUser?

    var body: some View {
        Group {
            switch model.blocked {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить") { Task { await model.loadBlocked() } }
                }
            case .loaded(let users) where users.isEmpty:
                ContentUnavailableView("Никого нет", systemImage: "hand.raised", description: Text("Заблокированные пользователи появятся здесь."))
            case .loaded(let users):
                List(users) { user in
                    HStack(spacing: 12) {
                        AvatarView(title: user.title, id: user.id, url: user.avatarURL, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.title)
                            if !user.phone.isEmpty {
                                Text(PhoneFormatting.format(user.phone))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Разблокировать") { pending = user }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            pending = user
                        } label: {
                            Label("Разблокировать", systemImage: "hand.raised.slash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Чёрный список")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadBlocked() }
        .refreshable { await model.loadBlocked() }
        .confirmationDialog(
            "Разблокировать \(pending?.title ?? "")?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Разблокировать") {
                if let user = pending { Task { await model.unblock(user) } }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}
