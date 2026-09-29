import SwiftUI
import OrbitlUI

struct AuthView: View {
    @Bindable var viewModel: AuthViewModel
    var expired: Bool

    var body: some View {
        NavigationStack {
            Form {
                if expired {
                    Text("Сессия истекла. Войдите снова. Переписка на устройстве сохранится, пока вы сами не выйдете.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                switch viewModel.step {
                case .codeSent(let length):
                    codeFields(length: length)
                case .password(let hint):
                    passwordFields(hint: hint)
                case .registration:
                    registerFields
                default:
                    phoneFields
                }
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Вход")
            .disabled(viewModel.isBusy)
            .overlay {
                if viewModel.isBusy { ProgressView() }
            }
        }
        .task { viewModel.activate() }
    }

    private var phoneFields: some View {
        Section("Телефон") {
            TextField("+7…", text: $viewModel.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            Button("Получить код") { Task { await viewModel.requestCode() } }
                .disabled(viewModel.phone.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func codeFields(length: Int?) -> some View {
        Section(length.map { "Код из \($0) цифр" } ?? "Код из SMS") {
            TextField("Код", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button("Продолжить") { Task { await viewModel.verify() } }
                .disabled(viewModel.code.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Отправить ещё раз") { Task { await viewModel.resendCode() } }
        }
    }

    private func passwordFields(hint: String?) -> some View {
        Section(hint.map { "Пароль (\($0))" } ?? "Пароль") {
            SecureField("Пароль", text: $viewModel.password)
            Button("Войти") { Task { await viewModel.submitPassword() } }
                .disabled(viewModel.password.isEmpty)
        }
    }

    private var registerFields: some View {
        Section("Новый аккаунт") {
            TextField("Имя", text: $viewModel.firstName)
            TextField("Фамилия", text: $viewModel.lastName)
            Button("Создать") { Task { await viewModel.register() } }
        }
    }
}
