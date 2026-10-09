import SwiftUI
import UIKit
import OrbitleDomain

/// Тема приложения на окне, в котором стоит этот вид: `overrideUserInterfaceStyle`.
///
/// Через окно тему получают и системные части (листы, меню, диалоги, строка состояния).
/// `preferredColorScheme(nil)` в SwiftUI для этого не годится: после светлой или тёмной темы
/// он не возвращает системную до перезапуска приложения.
struct InterfaceStyleOverride: UIViewRepresentable {
    let theme: ThemeMode

    func makeUIView(context: Context) -> WindowStyleView {
        let view = WindowStyleView()
        view.isUserInteractionEnabled = false
        view.style = theme.interfaceStyle
        return view
    }

    func updateUIView(_ view: WindowStyleView, context: Context) {
        view.apply(theme.interfaceStyle)
    }

    /// Пустой вид: ставит тему окну, как только попадает в него, и при каждой смене темы.
    final class WindowStyleView: UIView {
        var style: UIUserInterfaceStyle = .unspecified

        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.overrideUserInterfaceStyle = style
        }

        func apply(_ next: UIUserInterfaceStyle) {
            guard next != style else { return }
            style = next
            guard let window else { return }
            guard !UIAccessibility.isReduceMotionEnabled else {
                window.overrideUserInterfaceStyle = next
                return
            }
            UIView.transition(with: window, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                window.overrideUserInterfaceStyle = next
            }
        }
    }
}

extension ThemeMode {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
