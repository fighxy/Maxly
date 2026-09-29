import SwiftUI
import OrbitlDomain
import OrbitlPresentation
import OrbitlUI

/// Список чатов. Строки, папки, поиск, закреплённые и состояния готовит `ChatListViewModel`,
/// экран раскладывает их и передаёт действия обратно.
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selection: String?
    @State private var composeShown = false

    var body: some View {
        Group {
            if viewModel.isEditing {
                List(selection: $viewModel.editSelection) { content }
            } else {
                List(selection: $selection) { content }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(viewModel.isEditing ? .active : .inactive))
        // Новое сообщение поднимает строку наверх плавно, а не скачком.
        .animation(.default, value: viewModel.items.map(\.id))
        .animation(.default, value: viewModel.isSearchActive)
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.showsFolders, !viewModel.isSearchActive {
                FolderStrip(tabs: viewModel.folders, selected: viewModel.selectedFolderId) { id in
                    withAnimation { viewModel.selectFolder(id) }
                }
                .padding(.bottom, 4)
                .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing { editBar }
        }
        .overlay { placeholder }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(viewModel.isEditing || viewModel.isSearchActive ? .hidden : .visible, for: .tabBar)
        .refreshable { await viewModel.refresh() }
        .task {
            viewModel.activate()
            await viewModel.refresh()
        }
        .onChange(of: selection) { _, id in
            guard let id, viewModel.isSearchActive else { return }
            Task { await viewModel.selectSearchResult(chatId: id) }
        }
        .sheet(isPresented: $composeShown) { ComposeSheet() }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionShown,
            titleVisibility: .visible,
            presenting: viewModel.deletionCandidate
        ) { item in
            if item.type == .private {
                Button("Удалить у меня и у собеседника", role: .destructive) {
                    Task { await viewModel.confirmDelete(forEveryone: true) }
                }
            }
            Button(item.type == .private ? "Удалить только у меня" : "Удалить и выйти", role: .destructive) {
                Task { await viewModel.confirmDelete(forEveryone: false) }
            }
            Button("Отмена", role: .cancel) { viewModel.cancelDelete() }
        }
    }

    // MARK: Содержимое

    @ViewBuilder
    private var content: some View {
        FlatSearchField(text: $viewModel.searchQuery, isActive: $viewModel.isSearchActive)
            .listRowInsets(EdgeInsets(top: 4, leading: OrbitlTheme.pad, bottom: 8, trailing: OrbitlTheme.pad))
            .listRowSeparator(.hidden)
            .selectionDisabled()
        if viewModel.isSearchActive {
            searchResults
        } else {
            if let message = viewModel.inlineError {
                Button {
                    viewModel.dismissError()
                } label: {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .listRowSeparator(.hidden)
                .selectionDisabled()
                .accessibilityHint("Скрыть")
            }
            if let archive = viewModel.archive {
                NavigationLink {
                    ArchivedChatsView(viewModel: viewModel, selection: $selection)
                } label: {
                    ArchiveRow(summary: archive)
                }
                .listRowInsets(rowInsets)
                .alignmentGuide(.listRowSeparatorLeading) { _ in OrbitlTheme.separatorInset - OrbitlTheme.pad }
                .selectionDisabled()
            }
            if viewModel.content == .loading {
                ForEach(0..<8, id: \.self) { index in
                    ChatRowSkeleton(seed: index)
                        .listRowInsets(rowInsets)
                        .selectionDisabled()
                }
            }
            ForEach(viewModel.items) { item in
                row(item)
            }
            .onMove { source, destination in
                Task { await viewModel.movePinned(from: source, to: destination) }
            }
            if viewModel.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: OrbitlTheme.pad, bottom: 0, trailing: OrbitlTheme.pad)
    }

    private func row(_ item: ChatListItem) -> some View {
        ChatRow(item: item)
            .tag(item.id)
            .listRowInsets(rowInsets)
            .listRowBackground(item.isPinned ? Color.orbitlPinnedBackground : nil)
            .alignmentGuide(.listRowSeparatorLeading) { _ in OrbitlTheme.separatorInset - OrbitlTheme.pad }
            .moveDisabled(!(viewModel.canReorderPinned && item.isPinned))
            .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(item) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(item) }
            .contextMenu { menu(item) }
            .onAppear { Task { await viewModel.itemAppeared(item.id) } }
    }

    // MARK: Действия строки

    private func isUnread(_ item: ChatListItem) -> Bool {
        item.unreadCount > 0 || item.badge == .dot
    }

    @ViewBuilder
    private func leadingActions(_ item: ChatListItem) -> some View {
        if isUnread(item) {
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label("Прочитано", systemImage: "envelope.open.fill")
            }
            .tint(Color.orbitlAccent)
        } else if viewModel.capabilities.contains(.markUnread) {
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label("Непрочитано", systemImage: "envelope.badge.fill")
            }
            .tint(Color.orbitlAccent)
        }
        if viewModel.capabilities.contains(.pin) {
            Button { Task { await viewModel.togglePin(chatId: item.id) } } label: {
                Label(item.isPinned ? "Открепить" : "Закрепить", systemImage: item.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private func trailingActions(_ item: ChatListItem) -> some View {
        if viewModel.capabilities.contains(.delete) {
            Button(role: .destructive) { viewModel.requestDelete(chatId: item.id) } label: {
                Label("Удалить", systemImage: "trash.fill")
            }
        }
        if viewModel.capabilities.contains(.archive) {
            Button { Task { await viewModel.toggleArchive(chatId: item.id) } } label: {
                Label("В архив", systemImage: "archivebox.fill")
            }
            .tint(.gray)
        }
        if viewModel.capabilities.contains(.mute) {
            Button { Task { await viewModel.toggleMute(chatId: item.id) } } label: {
                Label(item.isMuted ? "Со звуком" : "Без звука", systemImage: item.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func menu(_ item: ChatListItem) -> some View {
        Button { selection = item.id } label: {
            Label("Открыть", systemImage: "bubble.left")
        }
        if isUnread(item) {
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label("Отметить прочитанным", systemImage: "envelope.open")
            }
        } else if viewModel.capabilities.contains(.markUnread) {
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label("Отметить непрочитанным", systemImage: "envelope.badge")
            }
        }
        if viewModel.capabilities.contains(.pin) {
            Button { Task { await viewModel.togglePin(chatId: item.id) } } label: {
                Label(item.isPinned ? "Открепить" : "Закрепить", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
        }
        if viewModel.capabilities.contains(.mute) {
            Button { Task { await viewModel.toggleMute(chatId: item.id) } } label: {
                Label(item.isMuted ? "Включить уведомления" : "Выключить уведомления", systemImage: item.isMuted ? "speaker.wave.2" : "speaker.slash")
            }
        }
        if viewModel.capabilities.contains(.archive) {
            Button { Task { await viewModel.toggleArchive(chatId: item.id) } } label: {
                Label("В архив", systemImage: "archivebox")
            }
        }
        if viewModel.capabilities.contains(.delete) {
            Button(role: .destructive) { viewModel.requestDelete(chatId: item.id) } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: Поиск

    @ViewBuilder
    private var searchResults: some View {
        let search = viewModel.search
        if viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            if !search.recent.isEmpty {
                Section {
                    ForEach(search.recent) { item in
                        ChatRow(item: item)
                            .tag(item.id)
                            .listRowInsets(rowInsets)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await viewModel.removeRecent(chatId: item.id) }
                                } label: {
                                    Label("Убрать", systemImage: "xmark")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Недавние")
                        Spacer()
                        Button("Очистить") { Task { await viewModel.clearRecent() } }
                            .font(.subheadline)
                            .foregroundStyle(Color.orbitlAccent)
                    }
                }
            }
        } else {
            if !search.chats.isEmpty {
                Section("Чаты") {
                    ForEach(search.chats) { item in
                        ChatRow(item: item)
                            .tag(item.id)
                            .listRowInsets(rowInsets)
                    }
                }
            }
            if !search.global.isEmpty || search.isSearchingServer {
                Section("Глобальный поиск") {
                    ForEach(search.global) { result in
                        GlobalResultRow(result: result)
                            .tag(result.id)
                    }
                    if search.isSearchingServer {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .selectionDisabled()
                    }
                }
            }
            if search.isEmpty, !search.isSearchingServer {
                ContentUnavailableView.search(text: viewModel.searchQuery)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
        }
    }

    // MARK: Панели

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(viewModel.isEditing ? "Готово" : "Изм.") {
                withAnimation { viewModel.isEditing.toggle() }
            }
            .fontWeight(viewModel.isEditing ? .semibold : .regular)
            .disabled(viewModel.items.isEmpty && !viewModel.isEditing)
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                if viewModel.connection != .online || viewModel.isCatchingUp {
                    ProgressView().controlSize(.small)
                }
                Text(viewModel.navigationTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                composeShown = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("Новое сообщение")
        }
    }

    private var editBar: some View {
        HStack {
            Button(viewModel.editSelection.isEmpty ? "Прочитать все" : "Прочитать (\(viewModel.editSelection.count))") {
                Task { await viewModel.readSelected() }
            }
            .disabled(viewModel.editSelection.isEmpty && viewModel.tabBadge == 0 && !viewModel.items.contains { $0.badge != nil })
            Spacer()
            if viewModel.capabilities.contains(.reorderPins), viewModel.pinnedCount > 1 {
                Text("Перетащите закреплённые, чтобы поменять порядок")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, OrbitlTheme.pad)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var placeholder: some View {
        if !viewModel.isSearchActive {
            switch viewModel.content {
            case .list, .loading:
                EmptyView()
            case .empty:
                if viewModel.isFolderEmpty {
                    ContentUnavailableView("В папке нет чатов", systemImage: "folder", description: Text("Здесь появятся чаты, подходящие под эту папку"))
                } else {
                    ContentUnavailableView {
                        Label("Нет чатов", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Здесь появятся ваши переписки")
                    } actions: {
                        Button("Написать сообщение") { composeShown = true }
                    }
                }
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

    // MARK: Удаление

    private var deletionShown: Binding<Bool> {
        Binding(
            get: { viewModel.deletionCandidate != nil },
            set: { if !$0 { viewModel.cancelDelete() } }
        )
    }

    private var deletionTitle: String {
        guard let item = viewModel.deletionCandidate else { return "" }
        return "Удалить чат «\(item.title)»?"
    }
}

/// Найденный на сервере чат, которого нет в списке.
private struct GlobalResultRow: View {
    let result: ChatSearchResult

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: result.title, id: result.id, url: result.avatarURL, size: OrbitlTheme.smallAvatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.body.weight(.semibold)).lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

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

/// Новое сообщение. Выбрать собеседника можно будет, когда появится список контактов.
private struct ComposeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Новое сообщение",
                systemImage: "square.and.pencil",
                description: Text("Выбор собеседника появится вместе со списком контактов. Пока напишите из существующего чата.")
            )
            .navigationTitle("Новое сообщение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
