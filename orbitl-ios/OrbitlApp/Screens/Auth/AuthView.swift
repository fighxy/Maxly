import SwiftUI
import OrbitlPresentation

/// Экран входа. Вся логика шагов в `AuthViewModel`, здесь только раскладка и фокус.
struct AuthView: View {
    @Bindable var viewModel: AuthViewModel

    private enum Field: Hashable {
        case phone, code, password, firstName, lastName
    }

    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.sessionExpired {
                    Section {
                        Text("Сессия истекла. Войдите снова. Переписка на устройстве сохранится, пока вы сами не выйдете.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                switch viewModel.step {
                case .phone:
                    phoneSection
                case .code:
                    codeSection
                case .password:
                    passwordSection
                case .registration:
                    registrationSection
                }
                if let message = viewModel.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    .accessibilityAddTraits(.isStaticText)
                }
            }
            .navigationTitle(viewModel.title)
            .toolbar {
                if viewModel.canGoBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Назад") { Task { await viewModel.goBack() } }
                    }
                }
                if viewModel.isBusy {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
        }
        .task { viewModel.activate() }
        .onChange(of: viewModel.step, initial: true) { _, step in
            focus = field(for: step)
        }
    }

    /// Куда поставить курсор на новом шаге.
    private func field(for step: AuthViewModel.Step) -> Field {
        switch step {
        case .phone: .phone
        case .code: .code
        case .password: .password
        case .registration: .firstName
        }
    }

    private var phoneSection: some View {
        Section {
            TextField("+7 900 000-00-00", text: $viewModel.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($focus, equals: .phone)
                .submitLabel(.continue)
                .onSubmit { Task { await viewModel.requestCode() } }
            Button("Получить код") { Task { await viewModel.requestCode() } }
                .disabled(!viewModel.canRequestCode)
        } header: {
            Text("Номер телефона")
        } footer: {
            Text(viewModel.phoneHint ?? "Пришлём код в SMS")
        }
    }

    private var codeSection: some View {
        Section {
            TextField("Код", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .submitLabel(.continue)
                .onSubmit { Task { await viewModel.verify() } }
            Button("Продолжить") { Task { await viewModel.verify() } }
                .disabled(!viewModel.canVerify)
            // Обратный отсчёт перерисовывается раз в секунду без таймера в модели.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button(viewModel.resendTitle(at: context.date)) {
                    Task { await viewModel.resendCode() }
                }
                .disabled(!viewModel.canResend(at: context.date))
                .monospacedDigit()
            }
        } header: {
            Text("Код из SMS")
        } footer: {
            Text(viewModel.codePrompt)
        }
    }

    private var passwordSection: some View {
        Section {
            SecureField("Пароль", text: $viewModel.password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await viewModel.submitPassword() } }
            Button("Войти") { Task { await viewModel.submitPassword() } }
                .disabled(!viewModel.canSubmitPassword)
        } header: {
            Text("Облачный пароль")
        } footer: {
            Text(viewModel.passwordPrompt)
        }
    }

    private var registrationSection: some View {
        Section {
            TextField("Имя", text: $viewModel.firstName)
                .textContentType(.givenName)
                .focused($focus, equals: .firstName)
                .submitLabel(.next)
                .onSubmit { focus = .lastName }
            TextField("Фамилия (необязательно)", text: $viewModel.lastName)
                .textContentType(.familyName)
                .focused($focus, equals: .lastName)
                .submitLabel(.done)
                .onSubmit { Task { await viewModel.register() } }
            Button("Создать аккаунт") { Task { await viewModel.register() } }
                .disabled(!viewModel.canRegister)
        } header: {
            Text("Новый аккаунт")
        } footer: {
            Text("Номер ещё не зарегистрирован. Укажите имя, его увидят собеседники.")
        }
    }
}
