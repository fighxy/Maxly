import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Участники» группы: все страницы по мере прокрутки, значки «владелец» и «админ»
/// (или подпись админа), поиск по имени. Касание открывает личный чат с участником.
struct ChatMembersView: View {
    @Bindable var model: ChatMembersListModel
    var onOpenDialog: ((DialogDraft) -> Void)?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.visible) { member in
                    row(member)
                        .task { await model.rowAppeared(member) }
                }
                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else if let error = model.errorMessage {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        Label(error, systemImage: "arrow.clockwise")
                            .font(.footnote)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .overlay {
                if model.visible.isEmpty, !model.isLoading, !model.query.isEmpty {
                    ContentUnavailableView.search(text: model.query)
                }
            }
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск участников")
            .navigationTitle("Участники")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово", action: onClose)
                }
            }
            .task { if model.members.isEmpty { await model.loadMore() } }
        }
    }

    private func row(_ member: ChatMemberEntry) -> some View {
        let dialog = model.dialog(with: member)
        return Button {
            if let dialog { onOpenDialog?(dialog) }
        } label: {
            HStack(spacing: 12) {
                AvatarView(title: member.name, id: member.id, url: member.avatarURL, size: 40)
                PrivateText(member.name, placeholder: "Участник")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge = member.badge {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dialog == nil || onOpenDialog == nil)
        .accessibilityHint(dialog == nil ? "" : "Открыть чат")
    }
}
