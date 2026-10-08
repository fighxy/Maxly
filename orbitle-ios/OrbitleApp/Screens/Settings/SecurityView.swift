import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Безопасность»: пароль и почта, семейная защита, конфиденциальность (блок «Дополнительно»,
/// безопасный режим и настройки MAX, секция «Информация»), приватный режим, чёрный список
/// (docs/privacy.md). Настройки конфига меняются сразу и откатываются при отказе сервера.
/// Приватный режим — локальная настройка устройства, сервер о нём не знает.
struct SecurityView: View {
    @Bindable var account: AccountSettingsModel
    @Bindable var model: SecuritySettingsModel
    @Bindable var privacy: PrivacySettingsModel
    @Bindable var ghost: GhostSettingsModel
    @Bindable var privateMode: PrivateModeSettings
    let makeEmailFlow: @MainActor () -> RecoveryEmailFlow
    @State private var emailFlow: RecoveryEmailFlow?
    @State private var passwordDraft = ""
    @State private var passwordHint = ""
    /// «Имена из адресной книги» (настройка устройства).
    @Environment(AddressBookNamesSync.self) private var addressBook: AddressBookNamesSync?

    var body: some View {
        List {
            passwordSection
            familySection
            ghostSection
            privacySection
            informationSection
            privateModeSection
            addressBookSection

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
        .task {
            privacy.activate()
            await model.loadTwoFactor()
        }
        .refreshable { await model.loadTwoFactor() }
        .sheet(isPresented: Binding(get: { emailFlow != nil }, set: { if !$0 { emailFlow = nil } })) {
            if let emailFlow {
                RecoveryEmailView(flow: emailFlow) { status in model.apply(status) }
            }
        }
        .alert(
            "Не получилось",
            isPresented: Binding(
                get: { account.errorMessage != nil || model.errorMessage != nil || privacy.errorMessage != nil },
                set: { if !$0 { account.errorMessage = nil; model.errorMessage = nil; privacy.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(account.errorMessage ?? model.errorMessage ?? privacy.errorMessage ?? "")
        }
    }

    /// Статус семейной защиты из `FAMILY_PROTECTION`. Мини-приложение защиты пока не открывается.
    private var familySection: some View {
        Section {
            LabeledContent {
                if privacy.settings.isKnown {
                    Text(privacy.familyProtection.title)
                } else {
                    ProgressView()
                }
            } label: {
                SettingsRowLabel("Семейная защита", systemImage: "figure.and.child.holdinghands", tint: .pink)
            }
        } footer: {
            switch privacy.familyProtection {
            case .off: Text("Мини-приложение семейной защиты ещё не открыто для сторонних клиентов MAX.")
            case .admin: Text("Вы управляете защитой другого профиля в официальном приложении MAX.")
            case .manageable: Text("Поиск по номеру, звонки, приглашения и контент меняет администратор защиты.")
            }
        }
    }

    /// «Дополнительно»: режим призрака, отметки о прочтении, свой онлайн в шапке настроек.
    private var ghostSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { ghost.ghostMode },
                set: { value in Task { await ghost.setGhostMode(value) } }
            )) {
                SettingsRowLabel("Режим призрака", systemImage: "eye.slash.circle.fill", tint: .purple)
            }
            Toggle(isOn: Binding(
                get: { ghost.hideReadReceipts },
                set: { value in Task { await ghost.setHideReadReceipts(value) } }
            )) {
                SettingsRowLabel("Не отправлять отметки о прочтении", systemImage: "text.badge.checkmark", tint: .blue)
            }
            Toggle(isOn: Binding(
                get: { ghost.showsOwnPresence },
                set: { ghost.setShowsOwnPresence($0) }
            )) {
                SettingsRowLabel("Показывать мой онлайн", systemImage: "antenna.radiowaves.left.and.right", tint: .green)
            }
        } header: {
            PrivacyPartHeader()
        } footer: {
            Text(ghostFooter)
        }
    }

    private var ghostFooter: String {
        var text = "Режим призрака скрывает ваш онлайн и то, что вы печатаете, записываете или отправляете файлы. Отправленные сообщения и реакции видны как обычно. Без отметок о прочтении у собеседника сообщения остаются непрочитанными и после выключения такими и останутся."
        if ghost.isLocalOnly {
            text += " Пока это только сохраняется на устройстве: режим заработает с обновлением ядра."
        }
        return text
    }

    /// Безопасный режим и четыре настройки MAX под ним, в порядке MAX.
    private var privacySection: some View {
        Section {
            if privacy.settings.isKnown {
                Toggle(isOn: Binding(
                    get: { privacy.settings.safeMode },
                    set: { value in Task { await privacy.setSafeMode(value) } }
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
            ForEach(PrivacyRow.main) { row in
                PrivacyRowLink(row: row, model: privacy)
            }
        } footer: {
            Text(privacyFooter)
        }
    }

    private var privacyFooter: String {
        var text = privacy.mainLockReason
            ?? "Безопасный режим: никто, кроме ваших контактов, не найдёт вас по номеру, не позвонит и не пригласит в чаты. Показывается только безопасный контент."
        if privacy.isLocalOnly {
            text += " Поиск по номеру, звонки, приглашения и контент пока сохраняются только на устройстве."
        }
        return text
    }

    /// «Информация»: кто видит статус «в сети» и номер.
    private var informationSection: some View {
        Section {
            ForEach(PrivacyRow.information) { row in
                PrivacyRowLink(row: row, model: privacy)
            }
        } header: {
            Text("Информация")
        }
    }

    /// Имена людей в чатах — как в телефонной книге. Книга не покидает устройство.
    @ViewBuilder
    private var addressBookSection: some View {
        if let addressBook {
            Section {
                Toggle(isOn: Binding(
                    get: { addressBook.isEnabled },
                    set: { value in Task { await addressBook.setEnabled(value) } }
                )) {
                    SettingsRowLabel("Имена из адресной книги", systemImage: "person.crop.rectangle.stack.fill", tint: .orange)
                }
            } footer: {
                Text("Люди в чатах подписаны так, как вы записали их в телефоне. Адресная книга остаётся на этом устройстве и никуда не отправляется. Нужен доступ к контактам.")
            }
        }
    }

    /// Приватный режим: скрывает названия чатов, аватары и тексты на этом устройстве.
    private var privateModeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { privateMode.isEnabled },
                // Строка «Вид» появляется и уходит плавно.
                set: { value in withAnimation(OrbitleMotion.quick(reduceMotion: OrbitleMotion.systemReducesMotion)) { privateMode.setEnabled(value) } }
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
            if model.passwordForm == .none, let status = model.twoFactor.value {
                if status.isEnabled {
                    Button("Сменить пароль") { model.openPasswordForm(.change) }
                    Button("Выключить пароль") { model.openPasswordForm(.disable) }
                } else {
                    Button("Включить пароль") { model.openPasswordForm(.enable) }
                }
            }
            if let notice = model.passwordNotice {
                Text(notice).foregroundStyle(Color.orbitleAccent)
            }
            passwordEditor
        } footer: {
            switch model.twoFactor {
            case .loaded(let status) where !status.isEnabled:
                Text("Пароль защищает вход с нового устройства.")
            case .loaded:
                Text("Почта нужна, чтобы восстановить доступ, если вы забудете пароль.")
            case .failed(let message):
                Text(message)
            case .loading:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var passwordEditor: some View {
        switch model.passwordForm {
        case .none:
            EmptyView()
        case .enable:
            SecureField("Пароль", text: $passwordDraft)
            TextField("Подсказка", text: $passwordHint)
            Button("Включить") {
                Task { await model.enablePassword(passwordDraft, hint: passwordHint) }
            }
            .disabled(model.passwordWorking)
        case .change:
            SecureField("Текущий пароль", text: $passwordDraft)
            SecureField("Новый пароль", text: $passwordHint)
            Button("Сменить") {
                Task { await model.changePassword(oldPassword: passwordDraft, newPassword: passwordHint) }
            }
            .disabled(model.passwordWorking)
        case .disable:
            SecureField("Пароль", text: $passwordDraft)
            Button("Выключить") {
                Task { await model.disablePassword(passwordDraft) }
            }
            .disabled(model.passwordWorking)
        }
        if model.passwordForm != .none {
            if let error = model.passwordError {
                Text(error).foregroundStyle(.red)
            }
            Button("Отмена") { model.closePasswordForm() }
                .disabled(model.passwordWorking)
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
