import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Поле ввода чата. С iOS 18 знает выделение: по нему над полем появляется панель разметки.
struct ComposerTextField: View {
    @Bindable var viewModel: ChatViewModel
    var focus: FocusState<Bool>.Binding

    var body: some View {
        if #available(iOS 18.0, *) {
            SelectingComposerField(viewModel: viewModel, focus: focus)
        } else {
            TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                .focused(focus)
        }
    }
}

@available(iOS 18.0, *)
private struct SelectingComposerField: View {
    @Bindable var viewModel: ChatViewModel
    var focus: FocusState<Bool>.Binding
    @State private var selection: TextSelection?

    var body: some View {
        TextField("Сообщение", text: $viewModel.draft, selection: $selection, axis: .vertical)
            .focused(focus)
            .onChange(of: selection) { _, new in
                viewModel.formatSelection = Self.range(new, in: viewModel.draft)
            }
            .onChange(of: viewModel.draft) { _, text in
                // Текст ушёл или сменился целиком: прежнее выделение больше не про него.
                if text.isEmpty { viewModel.formatSelection = nil }
            }
    }

    /// Выделение в смещениях UTF-16; пустое (просто курсор) — `nil`.
    static func range(_ selection: TextSelection?, in text: String) -> Range<Int>? {
        guard let selection, case .selection(let range) = selection.indices, !range.isEmpty else { return nil }
        guard let lower = range.lowerBound.samePosition(in: text.utf16),
              let upper = range.upperBound.samePosition(in: text.utf16),
              lower <= upper, upper <= text.utf16.endIndex else { return nil }
        let start = text.utf16.distance(from: text.utf16.startIndex, to: lower)
        let end = text.utf16.distance(from: text.utf16.startIndex, to: upper)
        return start < end ? start..<end : nil
    }
}

/// Панель разметки над полем: жирный, курсив, подчёркнутый, зачёркнутый, моноширинный,
/// ссылка и «Обычный». Видна, пока в поле что-то выделено; нажатая кнопка подсвечена.
struct ComposerFormatBar: View {
    @Bindable var viewModel: ChatViewModel
    @State private var linkShown = false
    @State private var linkText = ""
    @State private var linkRejected = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MessageMarkup.toolbar, id: \.self) { kind in
                button(kind)
            }
            Divider().frame(height: 22)
            Button {
                viewModel.clearFormat()
            } label: {
                Image(systemName: "textformat")
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canClearFormat)
            .opacity(viewModel.canClearFormat ? 1 : 0.4)
            .accessibilityLabel("Обычный текст")
        }
        .font(.system(size: 17, weight: .medium))
        .padding(.horizontal, 6)
        .orbitleGlassCapsule(interactive: false)
        .alert("Ссылка", isPresented: $linkShown) {
            TextField("https://", text: $linkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Готово") {
                if !viewModel.setLink(linkText) { linkRejected = true }
            }
            if viewModel.selectedLink != nil {
                Button("Убрать ссылку", role: .destructive) { viewModel.setLink("") }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Адрес для выделенного текста")
        }
        .alert("Это не похоже на ссылку", isPresented: $linkRejected) {
            Button("Понятно", role: .cancel) {}
        }
    }

    private func button(_ kind: TextSpan.Kind) -> some View {
        let active = viewModel.isFormatActive(kind)
        return Button {
            if kind == .link {
                linkText = viewModel.selectedLink ?? ""
                linkShown = true
            } else {
                viewModel.toggleFormat(kind)
            }
        } label: {
            Image(systemName: Self.symbol(kind))
                .foregroundStyle(active ? Color.orbitleAccent : Color.primary)
                .frame(width: 40, height: 40)
                .background(active ? Color.orbitleAccent.opacity(0.15) : .clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.title(kind))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    static func symbol(_ kind: TextSpan.Kind) -> String {
        switch kind {
        case .strong: "bold"
        case .emphasized: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        default: "textformat"
        }
    }

    static func title(_ kind: TextSpan.Kind) -> String {
        switch kind {
        case .strong: "Жирный"
        case .emphasized: "Курсив"
        case .underline: "Подчёркнутый"
        case .strikethrough: "Зачёркнутый"
        case .monospaced: "Моноширинный"
        case .link: "Ссылка"
        default: "Обычный"
        }
    }
}
