import SwiftUI
import OrbitlePresentation
import OrbitleUI

/// Выбор чата для пересылки: список чатов с поиском, «Отмена» сверху. С `allowsMultiple`
/// касание отмечает чаты, снизу комментарий и «Отправить»: каждое сообщение уйдёт в каждый
/// отмеченный чат.
struct ForwardPickerView: View {
    let targets: [ChatListItem]
    var allowsMultiple = false
    let onPick: (String) -> Void
    var onPickMany: (([String], String?) -> Void)? = nil
    let onCancel: () -> Void
    @State private var query = ""
    @State private var picked: [String] = []
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            List(filtered) { item in
                Button {
                    tap(item.id)
                } label: {
                    HStack(spacing: 12) {
                        ChatAvatarView(avatar: item.avatar, size: 44)
                        PrivateText(item.title, placeholder: PrivateModeMask.chatTitle(for: item))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if allowsMultiple {
                            Image(systemName: picked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(picked.contains(item.id) ? Color.orbitleAccent : Color.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked.contains(item.id) ? .isSelected : [])
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск чата")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if allowsMultiple, !picked.isEmpty { sendBar }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена", action: onCancel)
                }
            }
        }
    }

    private var title: String {
        guard allowsMultiple, !picked.isEmpty else { return "Переслать" }
        return "Выбрано чатов: \(picked.count)"
    }

    private func tap(_ id: String) {
        guard allowsMultiple else { return onPick(id) }
        if let index = picked.firstIndex(of: id) {
            picked.remove(at: index)
        } else {
            picked.append(id)
        }
    }

    /// Комментарий уходит первым в каждый чат, потом сообщения.
    private var sendBar: some View {
        HStack(spacing: 8) {
            TextField("Комментарий", text: $comment, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .orbitleGlassCapsule(interactive: false)
            Button {
                let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                onPickMany?(picked, text.isEmpty ? nil : text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.orbitleAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.vertical, 8)
    }

    private var filtered: [ChatListItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return targets }
        return targets.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }
}
