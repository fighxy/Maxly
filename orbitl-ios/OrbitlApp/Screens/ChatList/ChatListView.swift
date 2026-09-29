import SwiftUI
import OrbitlUI

struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selection: String?
    var onLogout: () -> Void

    var body: some View {
        List(viewModel.chats, selection: $selection) { chat in
            ChatRow(chat: chat)
                .tag(chat.id)
        }
        .navigationTitle("Чаты")
        .overlay {
            if viewModel.chats.isEmpty {
                ContentUnavailableView("Нет чатов", systemImage: "bubble.left.and.bubble.right", description: Text(viewModel.error?.localizedDescription ?? "Потяните вниз, чтобы обновить"))
            }
        }
        .toolbar {
            Button("Выйти", role: .destructive, action: onLogout)
        }
        .refreshable { await viewModel.refresh() }
        .task {
            viewModel.activate()
            await viewModel.refresh()
        }
    }
}
