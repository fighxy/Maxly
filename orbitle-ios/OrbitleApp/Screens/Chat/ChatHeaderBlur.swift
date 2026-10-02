import SwiftUI
import UIKit

/// Тонкая размытая полоса вдоль самого верхнего края экрана: под статус-баром, с коротким
/// тающим краем. Пузыри, уезжая вверх, мягко гаснут у края, а не обрезаются о статус-бар.
/// Ряд заголовка полоса не закрывает: капсула названия и круглые кнопки висят над лентой
/// сами, как в привычных мессенджерах. Касаний полоса не ловит.
struct ChatHeaderBlur: View {
    /// Высота тающего края под статус-баром.
    static let fade: CGFloat = 12

    var body: some View {
        // Высота — статус-бар окна, а не верхний отступ экрана: в отступ входит и панель
        // навигации, и полоса вышла бы толстой.
        let solid = Self.statusBarHeight
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                VStack(spacing: 0) {
                    Rectangle().frame(height: solid)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
            .frame(height: solid + Self.fade)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static var statusBarHeight: CGFloat {
        let top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
        return top > 0 ? top : 20
    }
}

extension View {
    /// Шапка чата без системной подложки, с тонкой размытой полосой у верхнего края.
    ///
    /// Материал, а не стекло iOS 26: кнопки панели уже стеклянные, стекло под стеклом
    /// Apple не советует. На iOS 26 у панели навигации есть свой мягкий край прокрутки;
    /// как он ложится поверх полосы, нужно проверить на устройстве (см. docs/profile.md).
    func chatHeaderBlur() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { ChatHeaderBlur() }
    }
}
