import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Чаты из архива.
struct ArchivedChatsView: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(viewModel.archivedItems) { item in
                ChatRow(item: item)
                    .tag(item.id)
                    .swipeActions {
                        if viewModel.capabilities.contains(.archive) {
                            Button { Task { await viewModel.toggleArchive(chatId: item.id) } } label: {
                                Label("Вернуть", systemImage: "tray.and.arrow.up.fill")
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Архив чатов")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.archivedItems.isEmpty {
                ContentUnavailableView("Архив пуст", systemImage: "archivebox")
            }
        }
    }
}
