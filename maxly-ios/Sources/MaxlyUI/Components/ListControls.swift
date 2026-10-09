import SwiftUI
import MaxlyPresentation

/// Поле поиска во всю ширину: серая капсула, в покое лупа и «Поиск» по
/// центру; при вводе — слева, с крестиком и «Отменой».
public struct FlatSearchField: View {
    @Binding private var text: String
    @Binding private var isActive: Bool
    private let placeholder: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glyph

    public init(text: Binding<String>, isActive: Binding<Bool>, placeholder: String = "Поиск") {
        _text = text
        _isActive = isActive
        self.placeholder = placeholder
    }

    /// Поле в покое: подсказка по центру.
    private var idle: Bool { !focused && !isActive && text.isEmpty }

    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                HStack(spacing: 6) {
                    if !idle {
                        magnifier
                    }
                    TextField(idle ? "" : placeholder, text: $text)
                        .focused($focused)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !text.isEmpty {
                        Button {
                            text = ""
                            focused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Очистить поиск")
                    }
                }
                if idle {
                    HStack(spacing: 6) {
                        magnifier
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Color.maxlyField, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { focused = true }
            if isActive {
                Button("Отмена") {
                    text = ""
                    focused = false
                    // В той же анимации возвращается панель вкладок и список чатов.
                    withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { isActive = false }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.maxlyAccent)
                .transition(.maxlyBar(edge: .trailing, reduceMotion: reduceMotion))
            }
        }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: isActive)
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: idle)
        .onChange(of: focused) { _, value in
            // Панель вкладок прячется той же анимацией, что и кнопка «Отмена», а не скачком.
            if value, !isActive {
                withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { isActive = true }
            }
        }
        .onChange(of: isActive, initial: true) { _, value in
            // Поиск можно включить снаружи (кнопкой с лупой): тогда поле получает фокус.
            focused = value
        }
    }

    /// Лупа переезжает из центра влево вместе с подсказкой.
    private var magnifier: some View {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
            .matchedGeometryEffect(id: "magnifier", in: glyph)
            .accessibilityHidden(true)
    }
}

/// Папки над списком: стеклянная капсула, внутри названия листаются по
/// горизонтали, выбранная — на серой «таблетке», которая переезжает к новой. Число
/// непрочитанных — бейджем рядом с названием.
public struct FolderStrip: View {
    private let tabs: [ChatFolderTab]
    private let selected: String
    private let onSelect: (String) -> Void
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Высота капсулы и «таблетки» в ней.
    public static let height: CGFloat = 40
    private static let inset: CGFloat = 4

    public init(tabs: [ChatFolderTab], selected: String, onSelect: @escaping (String) -> Void) {
        self.tabs = tabs
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .padding(Self.inset)
            }
            .frame(height: Self.height)
            .clipShape(Capsule())
            .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: selected)
            .onChange(of: selected, initial: true) { _, id in
                withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .maxlyGlassCapsule(interactive: false)
    }

    private func tabButton(_ tab: ChatFolderTab) -> some View {
        let isSelected = tab.id == selected
        return Button {
            onSelect(tab.id)
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let badge = tab.badge {
                    UnreadBadge(text: badge, muted: !isSelected)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: Self.height - Self.inset * 2)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(tab.id)
        .accessibilityLabel(tab.badge.map { "\(tab.title), \($0) непрочитанных" } ?? tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

public extension View {
    /// Круглая стеклянная подложка кнопки. На iOS 26 — системное стекло, раньше — материал.
    @ViewBuilder
    func maxlyGlassCircle(size: CGFloat = 44) -> some View {
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

    /// Стеклянная скруглённая плашка (панель ответа над полем ввода).
    @ViewBuilder
    func maxlyGlassRounded(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08)))
        }
        #else
        background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08)))
        #endif
    }

    /// Стеклянная капсула для группы кнопок (например, «поиск + добавить»). `interactive` —
    /// стекло отзывается на касание само; у капсулы-контейнера с кнопками внутри — нет.
    @ViewBuilder
    func maxlyGlassCapsule(interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
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

/// Группа стеклянных элементов: на iOS 26 `GlassEffectContainer`, чтобы соседнее стекло
/// рисовалось и сливалось вместе; раньше — просто содержимое.
public struct MaxlyGlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    /// Имя стекла внутри `MaxlyGlassGroup`: на iOS 26 появляющийся и исчезающий элемент
    /// перетекает из соседнего стекла и обратно, а не возникает отдельной каплей.
    /// Ставится после `maxlyGlassCircle` / `maxlyGlassCapsule`. Раньше iOS 26 ничего не делает.
    @ViewBuilder
    func maxlyGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

public extension View {
    /// Главная кнопка экрана. На iOS 26 — системное стекло с заливкой акцентом
    /// (`.glassProminent`), раньше — `.borderedProminent`. Выключенная кнопка
    /// серая сама по себе.
    @ViewBuilder
    func maxlyProminentButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glassProminent).foregroundStyle(Color.maxlyOnAccent)
        } else {
            buttonStyle(.borderedProminent).foregroundStyle(Color.maxlyOnAccent)
        }
        #else
        buttonStyle(.borderedProminent).foregroundStyle(Color.maxlyOnAccent)
        #endif
    }
}

/// Папки системным сегментированным переключателем (`Picker` в стиле `.segmented`).
///
/// Пока сегменты помещаются в ширину экрана, они растягиваются на всю строку; когда папок
/// много, переключатель сохраняет свою ширину и листается по горизонтали. Непрочитанные
/// видны числом в названии сегмента.
public struct FolderSegments: View {
    private let tabs: [ChatFolderTab]
    private let selected: String
    private let onSelect: (String) -> Void

    public init(tabs: [ChatFolderTab], selected: String, onSelect: @escaping (String) -> Void) {
        self.tabs = tabs
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            picker
                .padding(.horizontal, MaxlyTheme.pad)
            ScrollView(.horizontal, showsIndicators: false) {
                picker
                    .fixedSize()
                    .padding(.horizontal, MaxlyTheme.pad)
            }
        }
    }

    private var picker: some View {
        Picker("Папка", selection: Binding(get: { selected }, set: { onSelect($0) })) {
            ForEach(tabs) { tab in
                Text(Self.label(tab))
                    .tag(tab.id)
                    .accessibilityLabel(tab.badge.map { "\(tab.title), \($0) непрочитанных" } ?? tab.title)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    static func label(_ tab: ChatFolderTab) -> String {
        guard let badge = tab.badge else { return tab.title }
        return "\(tab.title) \(badge)"
    }
}
