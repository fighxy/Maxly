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
    public let presentationID = UUID()
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
        guard self.request == nil else { return }
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

    public func dismiss(presentationID: UUID) {
        guard request?.presentationID == presentationID else { return }
        dismiss()
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
            MessageMenuOverlay(request: request) { presenter.dismiss(presentationID: request.presentationID) }
                .id(request.presentationID)
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
    @State private var closing = false
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 46
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let reactionHeight: CGFloat = 52
    private static let menuWidth: CGFloat = 250
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
                if reactionBarWidth > 0 {
                    reactionBar
                        .frame(width: layout.reactions.width)
                        .scaleEffect(shown ? 1 : 0.6, anchor: request.isOutgoing ? .bottomTrailing : .bottomLeading)
                        .opacity(shown ? 1 : 0)
                        .position(x: layout.reactions.midX, y: layout.reactions.midY)
                }
                request.preview
                    .frame(width: layout.preview.width, height: layout.preview.height, alignment: .top)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .shadow(color: .black.opacity(shown ? 0.25 : 0), radius: 12, y: 4)
                    .position(
                        x: (shown ? layout.preview.minX : request.frame.minX - origin.x) + layout.preview.width / 2,
                        y: (shown ? layout.preview.minY : request.frame.minY - origin.y) + layout.preview.height / 2
                    )
                actions
                    .frame(width: layout.actions.width, height: layout.actions.height)
                    .scaleEffect(shown ? 1 : 0.6, anchor: request.isOutgoing ? .topTrailing : .topLeading)
                    .opacity(shown ? 1 : 0)
                    .position(x: layout.actions.midX, y: layout.actions.midY)
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        .task(id: closing) {
            guard closing else { return }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            onDismiss()
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.15)) { shown = true }
        }
    }

    // MARK: Раскладка

    private var items: [MessageMenuAction] {
        expanded ? request.primary + request.more : request.primary
    }

    private var showsMore: Bool { !request.more.isEmpty && !expanded }

    /// Высота списка: строки, отступы списка сверху и снизу и черта над «Ещё…».
    private var menuHeight: CGFloat {
        let rows = CGFloat(items.count + (showsMore ? 1 : 0))
        return rows * rowHeight + 8 + (showsMore ? 9 : 0)
    }

    /// Пузырь стоит на своём месте, пока ряд реакций сверху и пункты снизу влезают; иначе
    /// сдвигается, а слишком высокий — обрезается сверху вниз.
    private func placement(in size: CGSize, safe: EdgeInsets, origin: CGPoint) -> MessageMenuLayout {
        MessageMenuLayout(
            bounds: CGRect(x: safe.leading + Self.margin, y: safe.top + Self.margin,
                           width: max(0, size.width - safe.leading - safe.trailing - Self.margin * 2),
                           height: max(0, size.height - safe.top - safe.bottom - Self.margin * 2)),
            source: request.frame.offsetBy(dx: -origin.x, dy: -origin.y), outgoing: request.isOutgoing,
            actionHeight: menuHeight, actionWidth: Self.menuWidth,
            reactionWidth: reactionBarWidth, reactionHeight: reactionBarWidth > 0 ? Self.reactionHeight : 0)
    }

    // MARK: Реакции

    private var reactionChoices: [String] {
        guard let reactions = request.reactions else { return [] }
        var seen = Set<String>()
        return (reactions + (request.mine.map { [$0] } ?? [])).filter { seen.insert($0).inserted }
    }

    private var reactionBarWidth: CGFloat {
        let count = CGFloat(reactionChoices.count) + (request.onMoreReactions == nil ? 0 : 1)
        return count > 0 ? count * 44 + 12 : 0
    }

    private var reactionBar: some View {
        ScrollView(.horizontal) {
        HStack(spacing: 0) {
            ForEach(reactionChoices, id: \.self) { emoji in
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
        }
        .scrollIndicators(.hidden)
        .disabled(closing)
        .frame(height: Self.reactionHeight)
        .maxlyGlassCapsule(interactive: false)
    }

    // MARK: Пункты

    private var actions: some View {
        ScrollView {
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
        }
        .scrollBounceBehavior(.basedOnSize)
        .disabled(closing)
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
            .frame(minHeight: rowHeight - 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: rowHeight - 8)
        .padding(.vertical, 4)
    }

    // MARK: Закрытие

    /// Пункт выполняется после закрытия меню: листы и подтверждения открываются уже без него.
    private func run(_ action: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        onDismiss()
        action()
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.18)) { shown = false }
    }
}
