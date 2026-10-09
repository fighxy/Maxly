import SwiftUI
import MaxlyPresentation

private struct PrivateModeDisplayKey: EnvironmentKey {
    static let defaultValue: PrivateModeDisplay = .visible
}

public extension EnvironmentValues {
    /// Приватный режим для экранов ниже. Корень приложения кладёт сюда значение из настроек.
    /// Экраны, где данные открывают осознанно (настройки, профиль, открытое сообщение),
    /// возвращают `.visible`.
    var privateMode: PrivateModeDisplay {
        get { self[PrivateModeDisplayKey.self] }
        set { self[PrivateModeDisplayKey.self] = newValue }
    }
}

/// Сила размытия в виде «Размытие». Подобрана так, чтобы не читались даже крупные буквы.
public enum PrivateModeBlur {
    public static let text: CGFloat = 7
    public static let bubble: CGFloat = 12
    /// Доля размера аватара.
    public static let avatar: CGFloat = 0.14
}

public extension View {
    /// Размытие, только если приватный режим в виде «Размытие».
    func privateModeBlur(_ display: PrivateModeDisplay, radius: CGFloat = PrivateModeBlur.text) -> some View {
        blur(radius: display == .blur ? radius : 0)
    }
}

/// Имя или текст, которые приватный режим прячет: заглушка или размытый настоящий текст.
/// VoiceOver в обоих случаях читает заглушку.
public struct PrivateText: View {
    private let text: String
    private let placeholder: String
    @Environment(\.privateMode) private var display

    public init(_ text: String, placeholder: String) {
        self.text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        switch display {
        case .visible:
            Text(text)
        case .placeholder:
            Text(placeholder)
        case .blur:
            Text(text)
                .blur(radius: PrivateModeBlur.text)
                .accessibilityLabel(placeholder)
        }
    }
}

/// Пузырь ленты в приватном режиме. Закрытый рисует заглушку (`masked`) или размытый
/// настоящий пузырь; его кнопки и меню не работают, касание открывает сообщение (`onReveal`).
/// Открытый и пузырь без режима — обычный `real`.
public struct PrivateBubbleGate<Real: View, Masked: View>: View {
    @Environment(\.privateMode) private var display
    private let isRevealed: Bool
    private let accessibilityText: String
    private let onReveal: () -> Void
    private let real: Real
    private let masked: Masked

    public init(
        isRevealed: Bool,
        accessibilityText: String,
        onReveal: @escaping () -> Void,
        @ViewBuilder real: () -> Real,
        @ViewBuilder masked: () -> Masked
    ) {
        self.isRevealed = isRevealed
        self.accessibilityText = accessibilityText
        self.onReveal = onReveal
        self.real = real()
        self.masked = masked()
    }

    public var body: some View {
        if !display.isMasked {
            real
        } else if isRevealed {
            real.environment(\.privateMode, .visible)
        } else {
            closed
        }
    }

    @ViewBuilder
    private var hidden: some View {
        if display == .blur {
            real
                .environment(\.privateMode, .visible)
                .blur(radius: PrivateModeBlur.bubble)
        } else {
            masked
        }
    }

    private var closed: some View {
        hidden
            .allowsHitTesting(false)
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onReveal)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(PrivateModeMask.revealAccessibilityHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onReveal)
    }
}
