import SwiftUI
import MaxlyPresentation
import MaxlyUI

/// Шаг кода из SMS. Полный код отправляется сам. Кнопка «Продолжить» есть, только
/// если сервер не сообщил длину кода.
struct AuthCodeStep: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        AuthStepScroll {
            AuthWordmark()
            AuthHeader(title: "Введите код", subtitle: prompt)
            Button("Изменить номер") { viewModel.backToPhone() }
                .font(.body)
                .padding(.top, 8)
            OneTimeCodeField(code: $viewModel.code, length: viewModel.codeCellCount, isFocused: $isCodeFocused)
                .disabled(viewModel.isBusy)
                .padding(.top, 28)
            if viewModel.needsManualCodeSubmit {
                // Длина кода неизвестна: сам код не отправится, нужна кнопка.
                AuthPrimaryButton(
                    title: "Продолжить",
                    isEnabled: viewModel.canVerify,
                    isBusy: viewModel.isBusy
                ) {
                    await viewModel.verify()
                }
                .padding(.top, 24)
                resend
                    .padding(.top, 16)
            } else if viewModel.isBusy {
                ProgressView()
                    .padding(.top, 20)
            } else {
                resend
                    .padding(.top, 20)
            }
            AuthMessage(error: viewModel.errorMessage)
        }
        .onAppear { isCodeFocused = true }
        .onChange(of: viewModel.isBusy) { _, busy in
            // Пока код проверяется, поле выключено и теряет фокус. Неверный код
            // стирается, и клавиатура сразу возвращается для нового.
            if !busy { isCodeFocused = true }
        }
    }

    /// «Мы отправили код из 6 цифр на» и номер основным цветом.
    private var prompt: Text {
        guard let number = viewModel.sentToDisplay else { return Text(viewModel.codePrompt) }
        // Номер не переносится посередине.
        let unbroken = number.replacingOccurrences(of: " ", with: "\u{00A0}")
        let lead = viewModel.expectedCodeLength.map { "Мы отправили код из \($0) цифр на" } ?? "Мы отправили код на"
        return Text("\(lead) \(Text(verbatim: unbroken).foregroundStyle(.primary))")
    }

    /// Обратный отсчёт перерисовывается раз в секунду без таймера в модели.
    private var resend: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let available = viewModel.canResend(at: context.date)
            Button(viewModel.resendTitle(at: context.date)) {
                Task { await viewModel.resendCode() }
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(available ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .disabled(!available)
        }
    }
}

/// Ввод одноразового кода: обычное системное поле `.oneTimeCode` с цифровой
/// клавиатурой (iOS сама предлагает код из SMS), а цифры показываются по ячейкам.
struct OneTimeCodeField: View {
    @Binding var code: String
    let length: Int
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused)
                // Само поле невидимо: текст и курсор рисуют ячейки поверх.
                .foregroundStyle(Color.clear)
                .tint(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Код из SMS")
                .accessibilityValue(code.isEmpty ? "Пусто" : code.map(String.init).joined(separator: " "))

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { index in
                    cell(at: index)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
    }

    private func cell(at index: Int) -> some View {
        let digits = Array(code)
        let isCurrent = isFocused.wrappedValue && index == min(digits.count, length - 1) && digits.count < length
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.fill.tertiary)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, lineWidth: isCurrent ? 2 : 0)
            }
            .overlay {
                if index < digits.count {
                    Text(String(digits[index]))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: 48)
            .animation(.snappy(duration: 0.15), value: code)
    }
}
