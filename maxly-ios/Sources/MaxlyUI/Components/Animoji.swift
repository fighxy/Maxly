import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// Анимодзи чата: эмодзи → Lottie (`ChatViewModel.animoji`).
private struct AnimojiCatalogKey: EnvironmentKey {
    static let defaultValue: [String: URL] = [:]
}

/// Только что поставленная реакция и отметка «доиграла».
public struct ReactionBurstHost: Sendable {
    public var burst: ReactionBurst?
    public var onShown: @MainActor @Sendable (Int) -> Void

    public init(burst: ReactionBurst?, onShown: @escaping @MainActor @Sendable (Int) -> Void) {
        self.burst = burst
        self.onShown = onShown
    }
}

private struct ReactionBurstKey: EnvironmentKey {
    static let defaultValue = ReactionBurstHost(burst: nil, onShown: { _ in })
}

public extension EnvironmentValues {
    var animojiCatalog: [String: URL] {
        get { self[AnimojiCatalogKey.self] }
        set { self[AnimojiCatalogKey.self] = newValue }
    }

    var reactionBurst: ReactionBurstHost {
        get { self[ReactionBurstKey.self] }
        set { self[ReactionBurstKey.self] = newValue }
    }
}

/// Анимация реакции, которую пользователь только что поставил на сообщение `messageId`: один
/// проход Lottie над пузырём, затем `ReactionBurstHost.onShown`.
struct ReactionBurstOverlay: View {
    let messageId: String
    @Environment(\.reactionBurst) private var host
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let burst = host.burst, burst.messageId == messageId, !reduceMotion {
            AnimatedSticker(lottieURL: burst.lottieURL, stillURL: nil, size: 120, loops: false) { Color.clear }
                .id(burst.id)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task(id: burst.id) {
                    try? await Task.sleep(for: .seconds(2.2))
                    host.onShown(burst.id)
                }
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
