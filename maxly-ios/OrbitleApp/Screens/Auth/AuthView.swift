import SwiftUI
import OrbitlePresentation
import OrbitleUI

/// Вход и регистрация. Шаги живут в `AuthViewModel`, экран превращает их в стек
/// навигации: номер — корень, код, пароль и регистрация открываются поверх него,
/// поэтому «назад» — системная кнопка панели навигации.
struct AuthView: View {
    @Bindable var viewModel: AuthViewModel
    /// Закрыть вход. Передаётся, только когда экран открыт поверх приложения
    /// (например, добавление аккаунта). На первом экране свежего запуска кнопки нет.
    var onClose: (() -> Void)?

    var body: some View {
        NavigationStack(path: path) {
            AuthPhoneStep(viewModel: viewModel)
                .toolbar {
                    if let onClose {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("Закрыть")
                        }
                    }
                }
                .navigationDestination(for: AuthRoute.self) { route in
                    destination(route)
                        .navigationBarTitleDisplayMode(.inline)
                        // Только шеврон, без подписи «Назад».
                        .toolbarRole(.editor)
                }
        }
        .tint(Color.orbitleAccent)
        .task { viewModel.activate() }
    }

    @ViewBuilder
    private func destination(_ route: AuthRoute) -> some View {
        switch route {
        case .code: AuthCodeStep(viewModel: viewModel)
        case .password: AuthPasswordStep(viewModel: viewModel)
        case .registration: AuthRegistrationStep(viewModel: viewModel)
        }
    }

    /// Стек навигации — прямое отражение шага. Системное «назад» возвращает к номеру.
    private var path: Binding<[AuthRoute]> {
        Binding(
            get: { AuthRoute(viewModel.step).map { [$0] } ?? [] },
            set: { newPath in
                if newPath.isEmpty { viewModel.backToPhone() }
            }
        )
    }
}

/// Экраны поверх ввода номера.
enum AuthRoute: Hashable {
    case code, password, registration

    init?(_ step: AuthViewModel.Step) {
        switch step {
        case .phone: return nil
        case .code: self = .code
        case .password: self = .password
        case .registration: self = .registration
        }
    }
}

// MARK: Общие части шагов

/// Прокручиваемая колонка шага: на маленьком экране клавиатура не прячет кнопку.
struct AuthStepScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.never)
        .background(Color.orbitleBackground)
    }
}

/// Логотип и название приложения над заголовком шага.
struct AuthWordmark: View {
    var body: some View {
        VStack(spacing: 12) {
            OrbitleLogoTile(size: 88)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text(verbatim: "Maxly")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Заголовок шага и пояснение под ним.
struct AuthHeader: View {
    let title: String
    let subtitle: Text

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            subtitle
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Строка формы с разделителями как на экране номера.
struct AuthFieldRow<Content: View>: View {
    var showsTopDivider = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if showsTopDivider { Divider() }
            content
                .frame(minHeight: 52)
            Divider()
        }
    }
}

/// Широкая главная кнопка шага. Пока идёт запрос, вместо текста крутится индикатор.
struct AuthPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let isBusy: Bool
    let action: @MainActor () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Text(title)
                    .font(.headline)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .orbitleProminentButtonStyle()
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .disabled(!isEnabled || isBusy)
    }
}

/// Ошибка или подсказка под кнопкой.
struct AuthMessage: View {
    let error: String?
    var hint: String?

    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .accessibilityAddTraits(.isStaticText)
        } else if let hint {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
    }
}
