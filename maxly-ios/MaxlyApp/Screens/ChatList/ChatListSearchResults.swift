import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Поиск в списке чатов: недавние, найденные чаты, глобальный поиск и сообщения. Строки
/// встают прямо в `List` списка.
struct ChatListSearchResults: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selection: String?
    let rowInsets: EdgeInsets
    /// Найденное сообщение: чат откроется на нём.
    let onOpenMessage: (ChatSearchMessage) -> Void

    var body: some View {
        let search = viewModel.search
        if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if search.recent.isEmpty {
                Text("Поиск по чатам и сообщениям")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } else {
                HStack {
                    Text("Недавние").font(.app(.subheadline, .semibold))
                    Spacer()
                    Button("Очистить") { Task { await viewModel.clearRecent() } }
                        .buttonStyle(.plain)
                }
                .listRowSeparator(.hidden)
                .selectionDisabled()
                ForEach(search.recent) { item in
                    ChatRow(item: item)
                        .tag(item.id)
                        .listRowInsets(rowInsets)
                        .swipeActions {
                            Button("Убрать", systemImage: "xmark", role: .destructive) {
                                Task { await viewModel.removeRecent(chatId: item.id) }
                            }
                        }
                }
            }
        } else {
            if !search.chats.isEmpty {
                searchHeading("Чаты")
                ForEach(search.chats) { item in
                    ChatRow(item: item).tag(item.id).listRowInsets(rowInsets)
                }
            }
            if !search.global.isEmpty {
                searchHeading("Глобальный поиск")
                ForEach(search.global) { result in
                    GlobalResultRow(result: result).tag(result.id)
                }
            }
            if !search.messages.isEmpty {
                searchHeading("Сообщения")
                ForEach(search.messages) { message in
                    Button {
                        onOpenMessage(message)
                        selection = message.chatId
                    } label: {
                        FoundMessageRow(message: message).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .selectionDisabled()
                }
            }
            if search.isSearchingServer {
                HStack { Spacer(); ProgressView("Поиск…"); Spacer() }
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } else if search.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
        }
    }

    private func searchHeading(_ title: String) -> some View {
        Text(title)
            .font(.app(.subheadline, .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }
}

/// Найденный на сервере чат, которого нет в списке.
/// В приватном режиме вместо имени «Чат», подпись (ник, число участников) скрыта.
private struct GlobalResultRow: View {
    let result: ChatSearchResult
    @Environment(\.privateMode) private var privateMode

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: result.title, id: result.id, url: result.avatarURL, size: MaxlyTheme.smallAvatar)
            VStack(alignment: .leading, spacing: 2) {
                PrivateText(result.title, placeholder: PrivateModeMask.searchResultTitle)
                    .font(.app(.body, .semibold))
                    .lineLimit(1)
                if let subtitle = result.subtitle, !privateMode.isMasked {
                    Text(subtitle).font(.app(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Найденное на сервере сообщение. В приватном режиме вместо названия «Чат», текст скрыт.
private struct FoundMessageRow: View {
    let message: ChatSearchMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PrivateText(message.chatTitle, placeholder: PrivateModeMask.searchResultTitle)
                    .font(.app(.body, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !message.time.isEmpty {
                    Text(message.time)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            PrivateText(message.snippet, placeholder: PrivateModeMask.archivePreview)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
