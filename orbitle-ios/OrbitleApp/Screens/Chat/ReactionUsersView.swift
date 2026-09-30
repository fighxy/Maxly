import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Кто отреагировал»: люди с их реакцией, сверху отбор по реакции.
struct ReactionUsersView: View {
    @Bindable var model: ReactionUsersViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if model.tabs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            tab("Все", selected: model.filter == nil) { model.filter = nil }
                            ForEach(model.tabs, id: \.emoji) { reaction in
                                tab(
                                    "\(reaction.emoji) \(ReactionPalette.countText(reaction.count))",
                                    selected: model.filter == reaction.emoji
                                ) { model.filter = reaction.emoji }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                content
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", action: onClose)
                }
            }
            .task { await model.load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.orbitleAccent : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Повторить") { Task { await model.load() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        case .loaded:
            if let empty = model.emptyText {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.visible) { user in
                HStack(spacing: 12) {
                    AvatarView(title: ReactionUsersViewModel.name(of: user), id: user.userId, url: user.avatarURL, size: 36)
                    Text(ReactionUsersViewModel.name(of: user))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(user.emoji)
                        .font(.title3)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
