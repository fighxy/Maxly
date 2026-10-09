import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// Полный выбор реакции: сетка каталога сервера (пока он не загрузился — запасной набор).
/// Своя реакция выделена, повторное нажатие на неё снимает реакцию.
public struct ReactionPicker: View {
    private let catalog: [String]
    private let mine: String?
    private let onPick: (String) -> Void
    private let onClose: () -> Void

    public init(catalog: [String], mine: String?, onPick: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.catalog = catalog
        self.mine = mine
        self.onPick = onPick
        self.onClose = onClose
    }

    private var items: [String] {
        catalog.isEmpty ? ReactionPalette.fallback : catalog
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 64), spacing: 6)], spacing: 6) {
                    ForEach(items, id: \.self) { emoji in
                        Button {
                            onPick(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 48, height: 48)
                                .background(
                                    emoji == mine ? Color.maxlyAccent.opacity(0.22) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji)
                        .accessibilityAddTraits(emoji == mine ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .navigationTitle("Реакции")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: onClose)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
