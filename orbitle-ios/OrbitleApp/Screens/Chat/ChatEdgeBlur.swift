import SwiftUI
import UIKit
import OrbitleDomain
import OrbitleUI

/// Нижний край, как у популярных мессенджеров: не размытие, а лёгкий переход в фон экрана.
/// Лента почти не тронута до самых нижних кнопок: фон проявляется по плавной кривой на
/// `height` pt, начиная на `rise` выше верха нижних кнопок (`controlsTop`, глобальная
/// координата, её меряет `ChatView`), и под кнопками держится не выше `maxOpacity`.
///
/// Материал (как в f78668c) размазывал цвет пузыря над полем ввода в цветную дымку и брал
/// слишком много высоты. Цвет фона пузырь не окрашивает: он просто тает к низу.
/// С обоями лента тает не в ровный цвет, а в сами обои: здесь рисуется та же картинка ровно
/// на месте фона (`wallpaperFrame`, глобальные координаты, её меряет `ChatView`), поэтому
/// полосы на границе нет — пузыри просто уходят под обои.
/// Кладётся поверх ленты, но под кнопкой «вниз» и полем ввода; отступы ленты не меняет,
/// поэтому кнопка «вниз» не налезает на пузыри. Касаний не ловит.
struct ChatBottomBlur: View {
    /// Насколько переход начинается выше верха нижних кнопок.
    static let rise: CGFloat = 20
    /// Высота плавной части перехода; ниже фон ровный.
    static let height: CGFloat = 60
    /// Насколько фон закрывает ленту под кнопками: пузыри там ещё читаются.
    static let maxOpacity: Double = 0.7

    let controlsTop: CGFloat
    var wallpaper: ChatWallpaper = .plain
    /// Где на экране лежит фон с обоями. Пусто — ещё не измерен.
    var wallpaperFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let top = controlsTop - Self.rise - frame.minY
            let total = frame.height - top
            if controlsTop > 0, total > 1 {
                fill(in: frame)
                    .mask(alignment: .topLeading) {
                        LinearGradient(
                            stops: Self.stops(fade: min(Self.height, total) / total),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geo.size.width, height: total)
                        .offset(y: top)
                    }
            }
        }
        // До низа экрана под полем ввода и полосой «домой»; клавиатуру не перекрывает.
        .ignoresSafeArea(.container, edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Во что тает лента: обои на их же месте или ровный фон экрана.
    @ViewBuilder
    private func fill(in frame: CGRect) -> some View {
        if wallpaper.hasImage, wallpaperFrame.width > 0, wallpaperFrame.height > 0 {
            ChatWallpaperBackground(wallpaper: wallpaper)
                .frame(width: wallpaperFrame.width, height: wallpaperFrame.height)
                .offset(x: wallpaperFrame.minX - frame.minX, y: wallpaperFrame.minY - frame.minY)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        } else {
            Rectangle()
                .fill(Color.orbitleChatBackground)
                .frame(width: frame.width, height: frame.height)
        }
    }

    /// Сверху вниз: полностью прозрачно у верха, плавный (ease-in-out) рост на доле `fade`
    /// высоты, дальше ровно `maxOpacity`.
    static func stops(fade: CGFloat) -> [Gradient.Stop] {
        let span = min(max(fade, 0.01), 1)
        let curve: [(CGFloat, Double)] = [(0, 0), (0.2, 0.06), (0.4, 0.28), (0.6, 0.62), (0.8, 0.9), (1, 1)]
        var stops = curve.map { Gradient.Stop(color: .black.opacity(maxOpacity * $0.1), location: span * $0.0) }
        if span < 1 { stops.append(Gradient.Stop(color: .black.opacity(maxOpacity), location: 1)) }
        return stops
    }
}

extension View {
    /// На iOS 26 лента рисует свой край прокрутки под панелью навигации (затемнение с
    /// размытием — в тёмной теме это была заметная тёмная полоса за шапкой) и над нижними
    /// кнопками. Шапка имеет системную подложку, низ — `ChatBottomBlur`; эффекты краёв выключены,
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
