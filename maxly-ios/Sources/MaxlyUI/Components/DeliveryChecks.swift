import SwiftUI

/// Галочки доставки: тонкие, со скруглёнными концами. Одна — отправлено, цвета времени
/// рядом (наследует стиль); две внахлёст — прочитано, голубые (`maxlyReadMark`). Ширина одна
/// и та же, чтобы время не сдвигалось, когда вторая галочка появляется.
public struct DeliveryChecks: View {
    private let read: Bool
    private let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let size = CGSize(width: 16, height: 10)

    public init(read: Bool, lineWidth: CGFloat = 1.4) {
        self.read = read
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        ZStack(alignment: .leading) {
            CheckShape(full: true)
                .stroke(style: style)
                .frame(width: 11, height: Self.size.height)
                .offset(x: read ? 0 : 2.5)
            if read {
                // У второй галочки виден только длинный штрих: короткий прячется за первой.
                // Сдвиг — отступом, а не `offset`: переход ветки (маска прорисовки) ложится на
                // её рамку, а `offset` рамку не двигает. Маска оставалась на месте первой
                // галочки и навсегда срезала вторую до огрызка у её угла.
                CheckShape(full: false)
                    .stroke(style: style)
                    .frame(width: 11, height: Self.size.height)
                    .padding(.leading, 5)
                    .transition(.maxlyCheckDraw(reduceMotion: reduceMotion))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .foregroundStyle(read ? AnyShapeStyle(Color.maxlyReadMark) : AnyShapeStyle(.foreground))
        .accessibilityLabel(read ? "Прочитано" : "Отправлено")
    }
}

/// Галочка в рамке: короткий штрих вниз-вправо и длинный вверх-вправо.
struct CheckShape: Shape {
    /// `false` — только длинный штрих.
    var full: Bool

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 0.8, dy: 0.8)
        let corner = CGPoint(x: inset.minX + inset.width * 0.36, y: inset.maxY)
        var path = Path()
        if full {
            path.move(to: CGPoint(x: inset.minX, y: inset.minY + inset.height * 0.55))
            path.addLine(to: corner)
        } else {
            path.move(to: CGPoint(x: corner.x + 1.2, y: corner.y - 1.2))
        }
        path.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        return path
    }
}

/// Галочка прорисовывается слева направо: маска растягивается от левого края. Масштаб маски —
/// анимируемый эффект отрисовки, поэтому переход плавный без своей интерполяции.
private struct CheckReveal: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            Rectangle().scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading)
        }
    }
}

public extension AnyTransition {
    /// Появление галочки доставки: она прорисовывается слева направо. Уходит растворением.
    /// С «Уменьшением движения» — только растворение.
    static func maxlyCheckDraw(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: CheckReveal(progress: 0), identity: CheckReveal(progress: 1)),
            removal: .opacity
        )
    }
}
