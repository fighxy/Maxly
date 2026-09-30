import SwiftUI
import OrbitlePresentation
#if canImport(UIKit)
import UIKit
#endif

/// Кривые и переходы Orbitle — одни на всё приложение, чтобы движение было одинаковым.
/// Каждая учитывает «Уменьшение движения»: вместо сдвигов, масштаба и пружин — короткое
/// растворение. Правила — в `docs/animations.md`.
public enum OrbitleMotion {
    /// Пузыри и строки: появление, исчезновение, перестановка, схлопывание промежутка.
    public static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.34, bounce: 0.1)
    }

    /// Мелочи: бейджи, галочки, кнопки, панели над полем ввода, поиск.
    public static func quick(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.22)
    }

    /// Реакции и значки, которые «выпрыгивают» с лёгким отскоком.
    public static func pop(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.32, bounce: 0.3)
    }

    /// Проявление загруженной картинки и смена состояний экрана (загрузка → пусто → список).
    public static let fade: Animation = .easeOut(duration: 0.2)

    /// Анимация ленты для этого изменения или `nil`: первая страница, старая история сверху
    /// и смена окна появляются сразу, без движения.
    public static func transcript(_ change: CollectionChange, reduceMotion: Bool) -> Animation? {
        change.animatesTranscript ? standard(reduceMotion: reduceMotion) : nil
    }

    /// Анимация списка чатов для этого изменения или `nil`: первая загрузка, новая страница
    /// снизу и смена папки — сразу.
    public static func list(_ change: CollectionChange, reduceMotion: Bool) -> Animation? {
        change.animatesList ? standard(reduceMotion: reduceMotion) : nil
    }

    /// Системная настройка «Уменьшение движения» для `withAnimation` вне тела вида.
    @MainActor
    public static var systemReducesMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }
}

public extension AnyTransition {
    /// Пузырь ленты. Своё сообщение поднимается от поля ввода и чуть растёт от правого
    /// нижнего угла, чужое — всплывает у левого края. Удалённое сжимается к своему краю
    /// и растворяется, а промежуток схлопывается той же анимацией.
    static func orbitleBubble(outgoing: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let anchor: UnitPoint = outgoing ? .bottomTrailing : .bottomLeading
        let insertion = AnyTransition.opacity
            .combined(with: .offset(y: outgoing ? 24 : 14))
            .combined(with: .scale(scale: outgoing ? 0.9 : 0.95, anchor: anchor))
        let removal = AnyTransition.opacity
            .combined(with: .scale(scale: 0.8, anchor: anchor))
        return .asymmetric(insertion: insertion, removal: removal)
    }

    /// Бейджи, реакции, кнопки: появляются из точки и растворяются.
    static func orbitlePop(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity)
    }

    /// Панели над полем ввода и под заголовком: выезжают от своего края.
    static func orbitleBar(edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
