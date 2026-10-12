import SwiftUI
import Observation
import MaxlyPresentation
#if canImport(UIKit)
import UIKit
#endif

/// Пункт меню сообщения.
public struct MessageMenuAction: Identifiable {
    public var id: String { title }
    public let title: String
    public let systemImage: String
    public let destructive: Bool
    public let action: () -> Void

    public init(_ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.destructive = destructive
        self.action = action
    }
}

/// Долгое нажатие на сообщение: что показать над лентой (`MessageMenuHost`).
public struct MessageMenuRequest: Identifiable {
    public let id: String
    /// Место пузыря на экране (глобальные координаты).
    public let frame: CGRect
    public let isOutgoing: Bool
    /// Быстрые реакции; `nil` — реакции ставить нельзя.
    public let reactions: [String]?
    /// Своя реакция: в ряду отмечена, нажатие снимает её.
    public let mine: String?
    public let onReact: (String) -> Void
    /// «+» в ряду реакций: полный выбор.
    public let onMoreReactions: (() -> Void)?
    /// Главные пункты, как у WhatsApp: «Ответить», «Переслать», «Копировать», «Сведения», «Удалить».
    public let primary: [MessageMenuAction]
    /// Остальное — под «Ещё…».
    public let more: [MessageMenuAction]
    /// Копия пузыря, поднятая над размытой лентой.
    public let preview: AnyView
}

/// Открытое меню сообщения. Экран чата кладёт его в окружение ленты: тогда пузыри по
/// долгому нажатию открывают меню как в WhatsApp, а без него — системное контекстное меню.
@MainActor
@Observable
public final class MessageMenuPresenter {
    public private(set) var request: MessageMenuRequest?

    public init() {}

    public func present(_ request: MessageMenuRequest) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Клавиатура уходит: меню занимает экран.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        self.request = request
    }

    public func dismiss() {
        request = nil
    }
}

private struct MessageMenuPresenterKey: EnvironmentKey {
    static let defaultValue: MessageMenuPresenter? = nil
}

public extension EnvironmentValues {
    /// Меню сообщений экрана чата (`MessageMenuPresenter`); `nil` — системное контекстное меню.
    var messageMenuPresenter: MessageMenuPresenter? {
        get { self[MessageMenuPresenterKey.self] }
        set { self[MessageMenuPresenterKey.self] = newValue }
    }
}

/// Слой меню над экраном чата: читает только `request`, поэтому открытие меню не
/// пересобирает ленту.
public struct MessageMenuHost: View {
    let presenter: MessageMenuPresenter

    public init(presenter: MessageMenuPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if let request = presenter.request {
            MessageMenuOverlay(request: request) { presenter.dismiss() }
                .id(request.id)
        }
    }
}

/// Меню сообщения как в WhatsApp: лента размыта и притемнена, пузырь поднят на своём месте
/// (или сдвинут, чтобы всё влезло), над ним ряд реакций с «+», под ним пункты и «Ещё…».
/// Касание мимо закрывает меню.
struct MessageMenuOverlay: View {
    let request: MessageMenuRequest
    let onDismiss: () -> Void

    @State private var shown = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let reactionHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 46
    private static let menuWidth: CGFloat = 250
    private static let gap: CGFloat = 8
    private static let margin: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let layout = placement(in: proxy.size, safe: proxy.safeAreaInsets, origin: origin)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.25))
                    .opacity(shown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityLabel("Закрыть меню")
                    .accessibilityAddTraits(.isButton)
                if request.reactions != nil {
                    reactionBar
                        .fixedSize()
                        .scaleEffect(shown ? 1 : 0.6, anchor: request.isOutgoing ? .bottomTrailing : .bottomLeading)
                        .opacity(shown ? 1 : 0)
                        .position(x: layout.reactionCenterX, y: layout.reactionY + Self.reactionHeight / 2)
                }
                request.preview
                    .frame(width: request.frame.width, height: layout.previewHeight, alignment: .top)
                    .clipped()
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(shown ? 0.25 : 0), radius: 12, y: 4)
                    .position(
                        x: (shown ? layout.previewX : request.frame.minX - origin.x) + request.frame.width / 2,
                        y: (shown ? layout.previewY : request.frame.minY - origin.y) + layout.previewHeight / 2
                    )
                actions
                    .frame(width: Self.menuWidth)
                    .scaleEffect(shown ? 1 : 0.6, anchor: request.isOutgoing ? .topTrailing : .topLeading)
                    .opacity(shown ? 1 : 0)
                    .position(x: layout.menuCenterX, y: layout.menuY + layout.menuHeight / 2)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.15)) { shown = true }
        }
    }

    // MARK: Раскладка

    private struct Layout {
        var previewX: CGFloat
        var previewY: CGFloat
        var previewHeight: CGFloat
        var reactionY: CGFloat
        var reactionCenterX: CGFloat
        var menuY: CGFloat
        var menuHeight: CGFloat
        var menuCenterX: CGFloat
    }

    private var items: [MessageMenuAction] {
        expanded ? request.primary + request.more : request.primary
    }

    private var showsMore: Bool { !request.more.isEmpty && !expanded }

    /// Высота списка: строки, отступы списка сверху и снизу и черта над «Ещё…».
    private var menuHeight: CGFloat {
        let rows = CGFloat(items.count + (showsMore ? 1 : 0))
        return rows * Self.rowHeight + 8 + (showsMore ? 9 : 0)
    }

    /// Пузырь стоит на своём месте, пока ряд реакций сверху и пункты снизу влезают; иначе
    /// сдвигается, а слишком высокий — обрезается сверху вниз.
    private func placement(in size: CGSize, safe: EdgeInsets, origin: CGPoint) -> Layout {
        let top = safe.top + Self.margin
        let bottom = size.height - safe.bottom - Self.margin
        let reactionSpace = request.reactions == nil ? 0 : Self.reactionHeight + Self.gap
        let menuH = menuHeight
        let available = bottom - top - reactionSpace - Self.gap - menuH
        let previewH = max(60, min(request.frame.height, available))
        var y = request.frame.minY - origin.y
        y = max(y, top + reactionSpace)
        y = min(y, bottom - menuH - Self.gap - previewH)
        let x = request.frame.minX - origin.x
        let leading = request.isOutgoing ? x + request.frame.width : x
        let reactionWidth = reactionBarWidth
        let reactionX = request.isOutgoing
            ? min(leading - reactionWidth / 2, size.width - Self.margin - reactionWidth / 2)
            : max(leading + reactionWidth / 2, Self.margin + reactionWidth / 2)
        let menuX = request.isOutgoing
            ? min(leading - Self.menuWidth / 2, size.width - Self.margin - Self.menuWidth / 2)
            : max(leading + Self.menuWidth / 2, Self.margin + Self.menuWidth / 2)
        return Layout(
            previewX: x,
            previewY: y,
            previewHeight: previewH,
            reactionY: y - reactionSpace,
            reactionCenterX: min(max(reactionX, Self.margin + reactionWidth / 2), size.width - Self.margin - reactionWidth / 2),
            menuY: y + previewH + Self.gap,
            menuHeight: menuH,
            menuCenterX: min(max(menuX, Self.margin + Self.menuWidth / 2), size.width - Self.margin - Self.menuWidth / 2)
        )
    }

    // MARK: Реакции

    private var reactionBarWidth: CGFloat {
        let count = CGFloat(request.reactions?.count ?? 0) + (request.onMoreReactions == nil ? 0 : 1)
        return count * 44 + 12
    }

    private var reactionBar: some View {
        HStack(spacing: 0) {
            ForEach(request.reactions ?? [], id: \.self) { emoji in
                Button {
                    run { request.onReact(emoji) }
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.primary.opacity(emoji == request.mine ? 0.18 : 0)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji == request.mine ? "\(emoji), ваша реакция, убрать" : emoji)
            }
            if let more = request.onMoreReactions {
                Button {
                    run(more)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ещё реакции")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.reactionHeight)
        .maxlyGlassCapsule(interactive: false)
    }

    // MARK: Пункты

    private var actions: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item.title, systemImage: item.systemImage, destructive: item.destructive) { run(item.action) }
            }
            if showsMore {
                Divider().padding(.vertical, 4)
                row("Ещё…", systemImage: "ellipsis.circle", destructive: false) {
                    withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { expanded = true }
                }
            }
        }
        .padding(.vertical, 4)
        .maxlyGlassRounded(radius: 20)
    }

    private func row(_ title: String, systemImage: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .frame(height: Self.rowHeight - 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: Self.rowHeight - 8)
        .padding(.vertical, 4)
    }

    // MARK: Закрытие

    /// Пункт выполняется после закрытия меню: листы и подтверждения открываются уже без него.
    private func run(_ action: @escaping () -> Void) {
        onDismiss()
        action()
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18)) { shown = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }
}
