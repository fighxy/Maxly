import SwiftUI

/// Галочки доставки, как в Telegram: тонкие, со скруглёнными концами. Одна — отправлено,
/// две внахлёст — прочитано. Ширина одна и та же, чтобы время не сдвигалось, когда
/// вторая галочка появляется.
public struct DeliveryChecks: View {
    private let read: Bool
    private let lineWidth: CGFloat

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
                CheckShape(full: false)
                    .stroke(style: style)
                    .frame(width: 11, height: Self.size.height)
                    .offset(x: 5)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottomLeading)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
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
