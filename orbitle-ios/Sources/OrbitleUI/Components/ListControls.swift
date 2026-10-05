import SwiftUI
import OrbitlePresentation

/// Плоское поле поиска во всю ширину: серая скруглённая подложка, лупа, крестик и «Отмена».
public struct FlatSearchField: View {
    @Binding private var text: String
    @Binding private var isActive: Bool
    private let placeholder: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .background(Color.orbitleField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            if isActive {
                Button("Отмена") {
                    text = ""
                    focused = false
                    // В той же анимации возвращается панель вкладок и список чатов.
                    withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { isActive = false }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.orbitleAccent)
                .transition(.orbitleBar(edge: .trailing, reduceMotion: reduceMotion))
            }
        }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: isActive)
        .onChange(of: focused) { _, value in
            // Панель вкладок прячется той же анимацией, что и кнопка «Отмена», а не скачком.
            if value, !isActive {
                withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { isActive = true }
            }
        }
        .onChange(of: isActive) { _, value in
            // Поиск можно включить снаружи (кнопкой с лупой): тогда поле получает фокус.
            focused = value
        }
    }
}

/// Полоса папок над списком: название, число непрочитанных, подчёркивание выбранной.
public struct FolderStrip: View {
    private let tabs: [ChatFolderTab]
    private let selected: String
    private let onSelect: (String) -> Void
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                        .foregroundStyle(tab.id == selected ? Color.orbitleAccent : .secondary)
                                    if let badge = tab.badge {
                                        UnreadBadge(text: badge, muted: tab.id != selected)
                                            .scaleEffect(0.85)
                                    }
                                }
                                ZStack {
                                    Capsule().fill(Color.clear).frame(height: 3)
                                    if tab.id == selected {
                                        Capsule()
                                            .fill(Color.orbitleAccent)
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
                .padding(.horizontal, OrbitleTheme.pad)
                .padding(.top, 4)
            }
            .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: selected)
            .onChange(of: selected) { _, id in
                withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

public extension View {
    /// Круглая стеклянная подложка кнопки. На iOS 26 — системное стекло, раньше — материал.
    @ViewBuilder
    func orbitleGlassCircle(size: CGFloat = 44) -> some View {
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
    func orbitleGlassRounded(radius: CGFloat) -> some View {
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

    /// Стеклянная капсула для группы кнопок (например, «поиск + добавить»).
    @ViewBuilder
    func orbitleGlassCapsule() -> some View {
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

/// Группа стеклянных элементов: на iOS 26 `GlassEffectContainer`, чтобы соседнее стекло
/// рисовалось и сливалось вместе; раньше — просто содержимое.
public struct OrbitleGlassGroup<Content: View>: View {
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
    /// Имя стекла внутри `OrbitleGlassGroup`: на iOS 26 появляющийся и исчезающий элемент
    /// перетекает из соседнего стекла и обратно, а не возникает отдельной каплей.
    /// Ставится после `orbitleGlassCircle` / `orbitleGlassCapsule`. Раньше iOS 26 ничего не делает.
    @ViewBuilder
    func orbitleGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
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
    func orbitleProminentButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonStyle(.glassProminent).foregroundStyle(Color.orbitleOnAccent)
        } else {
            buttonStyle(.borderedProminent).foregroundStyle(Color.orbitleOnAccent)
        }
        #else
        buttonStyle(.borderedProminent).foregroundStyle(Color.orbitleOnAccent)
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
                .padding(.horizontal, OrbitleTheme.pad)
            ScrollView(.horizontal, showsIndicators: false) {
                picker
                    .fixedSize()
                    .padding(.horizontal, OrbitleTheme.pad)
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
