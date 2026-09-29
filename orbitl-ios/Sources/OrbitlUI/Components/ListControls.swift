import SwiftUI
import OrbitlPresentation

/// Плоское поле поиска во всю ширину: серая скруглённая подложка, лупа, крестик и «Отмена».
public struct FlatSearchField: View {
    @Binding private var text: String
    @Binding private var isActive: Bool
    private let placeholder: String
    @FocusState private var focused: Bool

    public init(text: Binding<String>, isActive: Binding<Bool>, placeholder: String = "Поиск") {
        _text = text
        _isActive = isActive
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(placeholder, text: $text)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.orbitlField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            if isActive {
                Button("Отмена") {
                    text = ""
                    focused = false
                    isActive = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.orbitlAccent)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isActive)
        .onChange(of: focused) { _, value in
            if value { isActive = true }
        }
        .onChange(of: isActive) { _, value in
            if !value { focused = false }
        }
    }
}

/// Полоса папок над списком: название, число непрочитанных, подчёркивание выбранной.
public struct FolderStrip: View {
    private let tabs: [ChatFolderTab]
    private let selected: String
    private let onSelect: (String) -> Void
    @Namespace private var underline

    public init(tabs: [ChatFolderTab], selected: String, onSelect: @escaping (String) -> Void) {
        self.tabs = tabs
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(tabs) { tab in
                        Button {
                            onSelect(tab.id)
                        } label: {
                            VStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Text(tab.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(tab.id == selected ? Color.orbitlAccent : .secondary)
                                    if let badge = tab.badge {
                                        UnreadBadge(text: badge, muted: tab.id != selected)
                                            .scaleEffect(0.85)
                                    }
                                }
                                ZStack {
                                    Capsule().fill(Color.clear).frame(height: 3)
                                    if tab.id == selected {
                                        Capsule()
                                            .fill(Color.orbitlAccent)
                                            .frame(height: 3)
                                            .matchedGeometryEffect(id: "underline", in: underline)
                                    }
                                }
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .id(tab.id)
                        .accessibilityLabel(tab.badge.map { "\(tab.title), \($0) непрочитанных" } ?? tab.title)
                        .accessibilityAddTraits(tab.id == selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, OrbitlTheme.pad)
                .padding(.top, 4)
            }
            .animation(.spring(duration: 0.3), value: selected)
            .onChange(of: selected) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

public extension View {
    /// Круглая стеклянная подложка кнопки. На iOS 26 — системное стекло, раньше — материал.
    @ViewBuilder
    func orbitlGlassCircle(size: CGFloat = 44) -> some View {
        let base = frame(width: size, height: size).contentShape(Circle())
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            base.glassEffect(.regular.interactive(), in: Circle())
        } else {
            base.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08)))
        }
        #else
        base.background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.08)))
        #endif
    }

    /// Стеклянная капсула для группы кнопок (например, «поиск + добавить»).
    @ViewBuilder
    func orbitlGlassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        }
        #else
        background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        #endif
    }
}
