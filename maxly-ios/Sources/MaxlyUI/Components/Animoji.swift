import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// Анимодзи чата: эмодзи → Lottie (`ChatViewModel.animoji`).
private struct AnimojiCatalogKey: EnvironmentKey {
    static let defaultValue: [String: URL] = [:]
}

/// Только что поставленная реакция на экране чата (`ChatViewModel.reactionBurst`): её значок в
/// плашке (`ReactionGlyph`) играет анимацию на месте и сообщает, где он в ленте; эффект вокруг
/// рисует `ReactionEffectLayer` поверх ленты, чтобы пузырь его не обрезал. Когда доиграли оба
/// (или вышел срок `limit`), `onShown`.
@MainActor
@Observable
public final class ReactionBurstHost {
    /// Пространство координат ленты: в нём значок сообщает своё место.
    public nonisolated static let space = "maxly.reactionBurst"
    public nonisolated static let limit: Duration = .seconds(4)

    public private(set) var burst: ReactionBurst?
    /// Где значок, в координатах `space`.
    var anchor: CGRect?
    private(set) var bodyDone = true
    private(set) var effectDone = true
    @ObservationIgnored public var onShown: @MainActor (Int) -> Void = { _ in }

    public init() {}

    public func update(_ next: ReactionBurst?) {
        guard next?.id != burst?.id else { return }
        burst = next
        anchor = nil
        bodyDone = next?.lottieURL == nil
        effectDone = next?.effectURL == nil
    }

    func bodyFinished(_ id: Int) {
        guard burst?.id == id else { return }
        bodyDone = true
        finishIfDone(id)
    }

    func effectFinished(_ id: Int) {
        guard burst?.id == id else { return }
        effectDone = true
        finishIfDone(id)
    }

    /// Анимация не загрузилась или значок не на экране — всё равно заканчиваем.
    public func expire(_ id: Int) {
        if burst?.id == id { onShown(id) }
    }

    private func finishIfDone(_ id: Int) {
        if bodyDone, effectDone { onShown(id) }
    }
}

private struct ReactionBurstKey: EnvironmentKey {
    static let defaultValue: ReactionBurstHost? = nil
}

public extension EnvironmentValues {
    var animojiCatalog: [String: URL] {
        get { self[AnimojiCatalogKey.self] }
        set { self[AnimojiCatalogKey.self] = newValue }
    }

    var reactionBurst: ReactionBurstHost? {
        get { self[ReactionBurstKey.self] }
        set { self[ReactionBurstKey.self] = newValue }
    }
}

/// Значок реакции `emoji` в плашке под сообщением `messageId`: эмодзи буквой. Только что
/// поставленная реакция один раз играет на месте свою анимацию (размер плашки не меняется) и
/// сообщает, где она в ленте, — для эффекта вокруг (`ReactionEffectLayer`). Так же, как в Komet.
struct ReactionGlyph: View {
    let messageId: String
    let emoji: String
    var size: CGFloat = 18
    @Environment(\.reactionBurst) private var host
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let host, let burst = host.burst, burst.matches(messageId: messageId, emoji: emoji), !reduceMotion {
            let playing = burst.lottieURL != nil && !host.bodyDone
            letter
                .opacity(playing ? 0 : 1)
                .overlay {
                    if playing, let url = burst.lottieURL {
                        AnimatedSticker(lottieURL: url, stillURL: nil, size: size, loops: false, onFinished: {
                            host.bodyFinished(burst.id)
                        }) { letter }
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ReactionBurstHost.space)) } action: { host.anchor = $0 }
                .id(burst.id)
        } else {
            letter
        }
    }

    private var letter: some View {
        Text(emoji).font(.system(size: 15))
    }
}

/// Эффект только что поставленной реакции (`lottiePlayUrl`) поверх ленты, по центру её значка:
/// крупный, не обрезается пузырём и едет вместе с лентой. Касаний не перехватывает.
public struct ReactionEffectLayer: View {
    let host: ReactionBurstHost
    var size: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(host: ReactionBurstHost, size: CGFloat = 72) {
        self.host = host
        self.size = size
    }

    public var body: some View {
        if let burst = host.burst, let url = burst.effectURL, !host.effectDone, let anchor = host.anchor, !reduceMotion {
            AnimatedSticker(lottieURL: url, stillURL: nil, size: size, loops: false, onFinished: {
                host.effectFinished(burst.id)
            }) { Color.clear }
                .id(burst.id)
                .position(x: anchor.midX, y: anchor.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Метка анимодзи в тексте (iOS 18+): по ней `AnimojiTextRenderer` находит место эмодзи.
@available(iOS 18.0, macOS 15.0, *)
struct AnimojiMark: TextAttribute {
    let url: URL
    let emoji: String
}

/// Где в тексте стоят анимодзи: рамки в координатах текста.
struct AnimojiFrame: Hashable, Sendable {
    let url: URL
    let emoji: String
    let rect: CGRect
}

/// Рамки анимодзи последнего рисования текста. Меняются только когда раскладка изменилась.
@MainActor
@Observable
final class AnimojiFrames {
    var frames: [AnimojiFrame] = []
}

/// Рисует текст, оставляя место анимодзи пустым, и сообщает их рамки: поверх них играет Lottie.
@available(iOS 18.0, macOS 15.0, *)
struct AnimojiTextRenderer: TextRenderer {
    let box: AnimojiFrames

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var found: [AnimojiFrame] = []
        for line in layout {
            for run in line {
                if let mark = run[AnimojiMark.self] {
                    found.append(AnimojiFrame(url: mark.url, emoji: mark.emoji, rect: run.typographicBounds.rect))
                } else {
                    context.draw(run)
                }
            }
        }
        let box = box
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if box.frames != found { box.frames = found }
            }
        }
    }
}

/// Lottie поверх мест анимодзи в тексте (iOS 18+). Пока анимация грузится — эмодзи буквой.
struct AnimojiOverlay: ViewModifier {
    let active: Bool
    @State private var box = AnimojiFrames()

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *), active {
            content
                .textRenderer(AnimojiTextRenderer(box: box))
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(box.frames.enumerated()), id: \.offset) { _, frame in
                            let side = max(frame.rect.width, frame.rect.height) * 1.1
                            AnimatedSticker(lottieURL: frame.url, stillURL: nil, size: side) {
                                Text(frame.emoji)
                            }
                            .position(x: frame.rect.midX, y: frame.rect.midY)
                        }
                    }
                    .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}
