import SwiftUI
import UIKit

/// Мягкое размытие у края ленты, как у популярных мессенджеров: материал проявляется по
/// плавной маске, без полосы с резкой границей. Пузыри, уезжая под край, мягко гаснут.
/// Касаний не ловит.
///
/// Материал, а не стекло iOS 26: капсулы шапки и поля ввода уже стеклянные, стекло под
/// стеклом Apple не советует.
struct ChatEdgeFade: View {
    enum Side { case top, bottom }

    let edge: Side
    /// Доля высоты от края, где материал ещё полный (под полем ввода — всё, что под ним).
    var solid: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: Self.stops(solid: solid),
                    startPoint: edge == .top ? .top : .bottom,
                    endPoint: edge == .top ? .bottom : .top
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Непрозрачность маски от края внутрь: полная до `solid`, дальше плавно (ease-out) к нулю.
    static func stops(solid: CGFloat) -> [Gradient.Stop] {
        let start = min(max(solid, 0), 0.95)
        let rest = 1 - start
        let curve: [(CGFloat, Double)] = [(0, 1), (0.25, 0.82), (0.5, 0.5), (0.75, 0.2), (1, 0)]
        var stops = [Gradient.Stop(color: .black, location: 0)]
        for (t, opacity) in curve {
            stops.append(Gradient.Stop(color: .black.opacity(opacity), location: start + rest * t))
        }
        return stops
    }
}

/// Верхний край: мягкое размытие только под статус-баром и чуть ниже. Ряд заголовка оно не
/// закрывает — капсула названия и круглые кнопки висят над лентой сами.
struct ChatHeaderBlur: View {
    /// Насколько размытие заходит ниже статус-бара.
    static let fade: CGFloat = 14

    var body: some View {
        // Высота — статус-бар окна, а не верхний отступ экрана: в отступ входит и панель
        // навигации, и размытие вышло бы полосой.
        ChatEdgeFade(edge: .top)
            .frame(height: Self.statusBarHeight + Self.fade)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }

    private static var statusBarHeight: CGFloat {
        let top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
        return top > 0 ? top : 20
    }
}

/// Нижний край: лента мягко размывается под полем ввода, плашкой «Включить уведомления» и
/// кнопкой «вниз». Начинается на `rise` выше верха нижних кнопок (`controlsTop`, глобальная
/// координата, её меряет `ChatView`) и идёт до низа экрана или до клавиатуры. Кладётся поверх
/// ленты, но под кнопкой «вниз» и полем ввода; отступы ленты не меняет, поэтому кнопка «вниз»
/// не налезает на пузыри.
struct ChatBottomBlur: View {
    /// Насколько размытие поднимается над нижними кнопками.
    static let rise: CGFloat = 28

    let controlsTop: CGFloat

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let top = controlsTop - Self.rise - frame.minY
            let height = frame.height - top
            if controlsTop > 0, height > Self.rise {
                ChatEdgeFade(edge: .bottom, solid: (height - Self.rise) / height)
                    .frame(width: geo.size.width, height: height)
                    .offset(y: top)
            }
        }
        // До низа экрана под полем ввода и полосой «домой»; клавиатуру не перекрывает.
        .ignoresSafeArea(.container, edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Шапка чата без системной подложки и без системного края прокрутки iOS 26 — только
    /// мягкое размытие под статус-баром.
    func chatHeaderBlur() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { ChatHeaderBlur() }
    }

    /// На iOS 26 лента рисует свой край прокрутки под панелью навигации (затемнение с
    /// размытием — в тёмной теме это была заметная тёмная полоса за шапкой) и над нижними
    /// кнопками. Края у ленты свои (`ChatHeaderBlur`, `ChatBottomBlur`), системные выключены,
    /// чтобы не ложиться вторым слоем. На iOS 17 и 18 такого края нет.
    @ViewBuilder
    func chatSystemEdgeEffectHidden() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: [.top, .bottom])
        } else {
            self
        }
    }
}
