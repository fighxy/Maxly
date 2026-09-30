import SwiftUI
import OrbitlePresentation
import OrbitleUI

/// Выбор чата для пересылки: список чатов с поиском, «Отмена» сверху.
struct ForwardPickerView: View {
    let targets: [ChatListItem]
    let onPick: (String) -> Void
    let onCancel: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filtered) { item in
                Button {
                    onPick(item.id)
                } label: {
                    HStack(spacing: 12) {
                        ChatAvatarView(avatar: item.avatar, size: 44)
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск чата")
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена", action: onCancel)
                }
            }
        }
    }

    private var filtered: [ChatListItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return targets }
        return targets.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }
}
