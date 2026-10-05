import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Аватар с кольцом историй: сегмент на историю, просмотренные — тусклые. Без кольца — обычный
/// аватар того же размера. `progress` — кольцо публикации вместо сегментов.
public struct StoryRingAvatar: View {
    private let avatar: ChatAvatar
    private let ring: StoryRing?
    private let size: CGFloat
    private let isOnline: Bool
    private let progress: Double?

    public init(avatar: ChatAvatar, ring: StoryRing?, size: CGFloat = OrbitleTheme.avatar, isOnline: Bool = false, progress: Double? = nil) {
        self.avatar = avatar
        self.ring = ring
        self.size = size
        self.isOnline = isOnline
        self.progress = progress
    }

    public var body: some View {
        if ring == nil && progress == nil {
            ChatAvatarView(avatar: avatar, size: size, isOnline: isOnline)
        } else {
            let stroke = min(max(size * 0.045, 2), 3.5)
            ZStack {
                StoryRingShape(ring: ring, progress: progress, stroke: stroke)
                ChatAvatarView(avatar: avatar, size: size - stroke * 4, isOnline: isOnline)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Сегменты кольца. Круглые концы съедают часть зазора, поэтому зазор шире на их угол.
private struct StoryRingShape: View {
    let ring: StoryRing?
    let progress: Double?
    let stroke: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: stroke / 2, dy: stroke / 2)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(red: 0.35, green: 0.78, blue: 0.98), Color(red: 0.20, green: 0.78, blue: 0.35)]),
                startPoint: CGPoint(x: 0, y: canvas.height),
                endPoint: CGPoint(x: canvas.width, y: 0)
            )
            let seen = GraphicsContext.Shading.color(.gray.opacity(0.4))
            if let progress {
                context.stroke(Path(ellipseIn: rect), with: seen, lineWidth: stroke)
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * min(max(progress, 0.02), 1)), clockwise: false)
                context.stroke(arc, with: gradient, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                return
            }
            guard let ring, radius > 0 else { return }
            let segments = StoryText.segments(ring)
            let step = 360.0 / Double(segments.count)
            let capDegrees = Double(stroke / radius) * 180 / .pi
            let gap = segments.count > 1 ? min(max(step * 0.12, 3), 10) + capDegrees : 0
            let style = StrokeStyle(lineWidth: stroke, lineCap: segments.count > 1 ? .round : .butt)
            for index in 0..<segments.count {
                let start = -90 + Double(index) * step + gap / 2
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: .degrees(start),
                           endAngle: .degrees(start + max(step - gap, 0.5)), clockwise: false)
                context.stroke(arc, with: index < segments.read ? seen : gradient, style: style)
            }
        }
        .accessibilityHidden(true)
    }
}
