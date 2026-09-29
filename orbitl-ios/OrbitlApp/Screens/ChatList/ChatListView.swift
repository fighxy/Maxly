import SwiftUI
import OrbitlPresentation
import OrbitlUI

/// Список чатов. Состояния, строки и плашку соединения готовит `ChatListViewModel`.
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selection: String?
    var onLogout: () -> Void

    var body: some View {
        List(selection: $selection) {
            if let banner = viewModel.banner {
                Label(banner, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            if let message = viewModel.inlineError {
                Button {
                    viewModel.dismissError()
                } label: {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .accessibilityHint("Скрыть")
            }
            ForEach(viewModel.items) { item in
                ChatRow(
                    title: item.title,
                    preview: item.preview,
                    time: item.time,
                    badge: item.unreadBadge,
                    accessibilityLabel: item.accessibilityLabel
                )
                .tag(item.id)
            }
        }
        .navigationTitle("Чаты")
        .overlay { placeholder }
        .toolbar {
            Button("Выйти", role: .destructive, action: onLogout)
        }
        .refreshable { await viewModel.refresh() }
        .task {
            viewModel.activate()
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch viewModel.content {
        case .list:
            EmptyView()
        case .loading:
            ProgressView("Загружаем чаты")
        case .empty:
            ContentUnavailableView("Нет чатов", systemImage: "bubble.left.and.bubble.right", description: Text("Здесь появятся ваши переписки"))
        case .offline:
            ContentUnavailableView {
                Label("Нет соединения", systemImage: "wifi.slash")
            } description: {
                Text("Чаты загрузятся, когда появится сеть")
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Не удалось загрузить чаты", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") { Task { await viewModel.refresh() } }
            }
        }
    }
}
