import SwiftUI

/// Размытая полоса под шапкой чата: на всю ширину от верхнего края экрана через
/// статус-бар и ряд заголовка. Лента уходит под неё и размывается, нижний край тает
/// на `fade` пунктов. Капсула названия и круглые кнопки остаются поверх: они живут в
/// панели навигации, а полоса — в содержимом экрана и касаний не ловит.
struct ChatHeaderBlur: View {
    /// Высота тающего края под панелью навигации.
    static let fade: CGFloat = 28

    var body: some View {
        // Читатель геометрии сам выходит за верхний край: его `safeAreaInsets.top` — это
        // статус-бар вместе с панелью навигации, а содержимое встаёт от края экрана.
        // Сдвигать полосу вверх ещё раз не нужно, иначе она уезжает за экран.
        GeometryReader { geo in
            let solid = geo.safeAreaInsets.top
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    VStack(spacing: 0) {
                        Rectangle().frame(height: solid)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.fade)
                    }
                }
                .frame(width: geo.size.width, height: solid + Self.fade)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Шапка чата без системной подложки, с размытой полосой под ней.
    ///
    /// Материал, а не стекло iOS 26: кнопки панели уже стеклянные, стекло под стеклом
    /// Apple не советует. На iOS 26 у панели навигации есть свой мягкий край прокрутки;
    /// как он ложится поверх полосы, нужно проверить на устройстве (см. docs/profile.md).
    func chatHeaderBlur() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { ChatHeaderBlur() }
    }
}
