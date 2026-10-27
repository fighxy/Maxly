import SwiftUI
import MaxlyUI

/// Нижняя панель вкладок на iPhone: компактная стеклянная капсула по ширине вкладок, а не
/// системная панель во всю ширину экрана. Выбранная вкладка — на подложке, которая переезжает
/// к новой (`matchedGeometryEffect`); число непрочитанных — бейджем у значка.
///
/// Панель стоит на корневом экране вкладки (`compactTabBar`), поэтому уезжает вместе с ним,
/// когда поверх открывается чат или другой экран, и возвращается вместе со свайпом назад.
/// Под ней — мягкое размытие низа (`BottomBarBackdrop`), как под закреплёнными папками сверху.
struct CompactTabBar: View {
    @Binding var selection: AppTab
    let badge: (AppTab) -> Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.order, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(Self.inset)
        .maxlyGlassCapsule(interactive: false)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = selection == tab
        let count = badge(tab)
        return Button {
            guard !selected else { return }
            withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 { badgeView(count) }
                    }
                Text(tab.title)
                    .font(.app(size: 10, .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.maxlyAccent : Color.primary)
            .frame(width: Self.itemWidth, height: Self.itemHeight)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "tab", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badgeView(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.app(size: 11, .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.red, in: Capsule())
            .fixedSize()
            .offset(x: 12, y: -5)
    }

    /// Ширина и высота одной вкладки, поле капсулы вокруг них.
    static let itemWidth: CGFloat = 72
    static let itemHeight: CGFloat = 48
    static let inset: CGFloat = 4
    /// Высота всей панели: ей лента и списки освобождают место снизу.
    static let height: CGFloat = itemHeight + inset * 2
}

/// Мягкое размытие под нижней панелью: материал панели проявляется к низу экрана по плавной
/// маске, без полосы с резкой границей. То же, что под закреплёнными папками сверху
/// (`PinnedHeaderBackdrop`), только снизу вверх. Касаний не ловит.
struct BottomBarBackdrop: View {
    /// Насколько размытие поднимается выше панели.
    static let rise: CGFloat = 24

    var body: some View {
        Rectangle()
            .fill(.bar)
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45), .init(color: .black, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.top, -Self.rise)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Компактная панель вкладок снизу корневого экрана вкладки (`CompactTabBar`). Пока
    /// `shown` ложно (правка или поиск в списке чатов), панели и места под неё нет.
    func compactTabBar(_ shown: Bool, selection: Binding<AppTab>, badge: @escaping (AppTab) -> Int) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if shown {
                CompactTabBar(selection: selection, badge: badge)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .background { BottomBarBackdrop() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
