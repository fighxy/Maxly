import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Список чатов. Строки, папки, поиск, закреплённые и состояния готовит `ChatListViewModel`,
/// экран раскладывает их и передаёт действия обратно.
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selection: String?
    var newChat: NewChatModel?
    var onOpened: (NewChatOpened) -> Void = { _ in }
    /// Найденное сообщение: чат откроется на нём. По умолчанию — просто чат.
    var onOpenMessage: (ChatSearchMessage) -> Void = { _ in }
    /// Свой аватар для плитки «Ваша история» и кнопка новой истории; без них полосы нет.
    var selfAvatar: ChatAvatar?
    var onAddStory: (() -> Void)?
    @State private var composeShown = false
    /// Истории: полоса над чатами и кольца на аватарах личных чатов. `nil` в превью.
    @Environment(StoriesViewModel.self) private var stories: StoriesViewModel?
    /// Настройка приватного режима для плавающей кнопки. `nil` в превью без контейнера.
    @Environment(PrivateModeSettings.self) private var privateModeSettings: PrivateModeSettings?
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Явное скрытие через заголовок. Прокрутка полосы не меняет эту настройку.
    @AppStorage("stories.stripCollapsed") private var storiesCollapsed = false
    var body: some View {
        chatList
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.isSearchActive)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing { editBar }
        }
        .overlay(alignment: .bottomTrailing) { privateModeButton }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task {
            viewModel.activate()
            await viewModel.refresh()
        }
        // Аватары первых строк качаются заранее: при прокрутке они проявляются сразу.
        .task(id: viewModel.itemsVersion) {
            let urls = viewModel.prefetchImageURLs()
            guard !urls.isEmpty else { return }
            await ImagePipeline.shared.prefetch(urls)
        }
        .onChange(of: selection) { _, id in
            guard let id, viewModel.isSearchActive else { return }
            Task { await viewModel.selectSearchResult(chatId: id) }
        }
        .sheet(isPresented: $composeShown, onDismiss: { newChat?.dismiss() }) {
            if let newChat {
                NewChatSheet(model: newChat) { opened in
                    newChat.consumeOpened()
                    composeShown = false
                    onOpened(opened)
                }
                .task {
                    newChat.show()
                    newChat.activate()
                }
            } else {
                ComposeSheet()
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionShown,
            titleVisibility: .visible,
            presenting: viewModel.deletionCandidate
        ) { item in
            eraseButtons(item, clearing: false)
            Button("Отмена", role: .cancel) { viewModel.cancelDelete() }
        }
        .confirmationDialog(
            clearTitle,
            isPresented: clearShown,
            titleVisibility: .visible,
            presenting: viewModel.clearCandidate
        ) { item in
            eraseButtons(item, clearing: true)
            Button("Отмена", role: .cancel) { viewModel.cancelClear() }
        }
    }

    /// Один List сохраняет состояние прокрутки при переключении edit mode.
    private var listSelection: Binding<Set<String>> {
        Binding(
            get: { viewModel.isEditing ? viewModel.editSelection : Set(selection.map { [$0] } ?? []) },
            set: { ids in
                if viewModel.isEditing { viewModel.editSelection = ids }
                // Касание может добавить строку к уже выбранной (открытый чат на iPad):
                // открыть новую, а не случайную из набора.
                else { selection = ids.first { $0 != selection } ?? ids.first }
            }
        )
    }

    // MARK: Содержимое

    /// Истории — обычная строка того же List: уходят вверх вместе с контентом.
    /// Нет второго вертикального жеста и изменения высоты списка под пальцем.
    @ViewBuilder
    private var storyStrip: some View {
        if let stories, let selfAvatar, let onAddStory,
           !storiesCollapsed, !viewModel.isSearchActive, !viewModel.isEditing {
            StoriesStrip(stories: stories, selfAvatar: selfAvatar, onAdd: onAddStory)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .selectionDisabled()
        }
    }

    private var chatChrome: some View {
        VStack(spacing: 0) {
            FlatSearchField(text: $viewModel.searchQuery, isActive: $viewModel.isSearchActive)
                .padding(.horizontal, OrbitleTheme.pad)
                .padding(.top, 4)
                .padding(.bottom, 8)
            if viewModel.showsFolders, !viewModel.isSearchActive {
                FolderStrip(tabs: viewModel.folders, selected: viewModel.selectedFolderId) { id in
                    viewModel.selectFolder(id)
                }
            }
        }
        .padding(.bottom, 4)
        // Закреплённая шапка полупрозрачная, как панель навигации над ней: строки под ней видны
        // размытыми, а не обрываются о сплошной фон.
        .background(.bar)
        .textCase(nil)
    }

    private var chatList: some View {
        List(selection: listSelection) {
            storyStrip
            Section {
                rows
            } header: {
                chatChrome
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.editMode, .constant(viewModel.isEditing ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .animation(OrbitleMotion.list(viewModel.itemsChange, reduceMotion: reduceMotion), value: viewModel.itemsVersion)
        .refreshable {
            await viewModel.refresh()
            await stories?.refresh()
        }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.isSearchActive {
            searchResults
        } else {
            placeholder
                .listRowSeparator(.hidden)
                .selectionDisabled()
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in OrbitleTheme.separatorInset - OrbitleTheme.pad }
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
        EdgeInsets(top: 0, leading: OrbitleTheme.pad, bottom: 0, trailing: OrbitleTheme.pad)
    }

    /// Чьи истории на аватаре строки.
    private func storyMatch(_ item: ChatListItem) -> (id: String, kind: StoryOwner.Kind)? {
        switch item.type {
        case .private:
            guard let peer = stories?.peer(ofChat: item.id, type: item.type) else { return nil }
            return (peer, .user)
        case .group:
            return (item.id, .chat)
        case .channel:
            return (item.id, .channel)
        }
    }

    private func row(_ item: ChatListItem) -> some View {
        // Кольцо на аватаре: человек, группа или канал. Касание открывает истории.
        let match = storyMatch(item)
        let ring = match.flatMap { stories?.ring(of: $0.id, kind: $0.kind) }
        var openStories: (() -> Void)?
        if let match, let stories { openStories = { stories.open(match.id, kind: match.kind) } }
        return ChatRow(item: item, storyRing: ring, onStoryTap: openStories)
            .tag(item.id)
            .listRowInsets(rowInsets)
            .listRowBackground(item.isPinned ? Color.orbitlePinnedBackground : nil)
            .alignmentGuide(.listRowSeparatorLeading) { _ in OrbitleTheme.separatorInset - OrbitleTheme.pad }
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
            .tint(Color.orbitleAccent)
        } else if viewModel.capabilities.contains(.markUnread) {
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label("Непрочитано", systemImage: "envelope.badge.fill")
            }
            .tint(Color.orbitleAccent)
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
            Button { viewModel.requestClear(chatId: item.id) } label: {
                Label("Очистить историю", systemImage: "eraser")
            }
            Button(role: .destructive) { viewModel.requestDelete(chatId: item.id) } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: Поиск

    @ViewBuilder
    private var searchResults: some View {
        let search = viewModel.search
        if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if search.recent.isEmpty {
                Text("Поиск по чатам и сообщениям")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } else {
                HStack {
                    Text("Недавние").font(.subheadline.weight(.semibold))
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .listRowSeparator(.hidden)
            .selectionDisabled()
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
            Button {
                withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { storiesCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.connection != .online || viewModel.isCatchingUp {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.navigationTitle).font(.headline)
                    if stories != nil, !viewModel.isSearchActive, !viewModel.isEditing {
                        Image(systemName: storiesCollapsed ? "chevron.down" : "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(stories == nil || viewModel.isSearchActive || viewModel.isEditing)
            .accessibilityLabel(viewModel.navigationTitle)
            .accessibilityHint(storiesCollapsed ? "Показать истории" : "Скрыть истории")
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
        .padding(.horizontal, OrbitleTheme.pad)
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

    // MARK: Приватный режим

    /// Плавающая стеклянная кнопка с глазом: включает и выключает приватный режим одним нажатием.
    /// Прячется при правке и поиске, а в «Безопасности» её можно убрать совсем.
    @ViewBuilder
    private var privateModeButton: some View {
        if let settings = privateModeSettings, settings.showsQuickToggle,
           !viewModel.isEditing, !viewModel.isSearchActive {
            Button {
                withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { settings.toggle() }
            } label: {
                Image(systemName: settings.isEnabled ? "eye.slash.fill" : "eye")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(settings.isEnabled ? Color.orbitleAccent : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .orbitleGlassCircle(size: 52)
            .padding(.trailing, OrbitleTheme.pad)
            .padding(.bottom, 12)
            .accessibilityLabel(settings.isEnabled ? "Выключить приватный режим" : "Включить приватный режим")
            .transition(.orbitlePop(reduceMotion: reduceMotion))
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
        // Название чата не должно всплыть в диалоге, пока включён приватный режим.
        if privateMode.isMasked { return "Удалить этот чат?" }
        return "Удалить чат «\(item.title)»?"
    }

    private var clearShown: Binding<Bool> {
        Binding(
            get: { viewModel.clearCandidate != nil },
            set: { if !$0 { viewModel.cancelClear() } }
        )
    }

    private var clearTitle: String {
        "Очистить историю?"
    }

    /// «Только у меня» всегда. «У всех» — кроме «Избранного», где собеседника нет.
    @ViewBuilder
    private func eraseButtons(_ item: ChatListItem, clearing: Bool) -> some View {
        let saved = item.id == Chat.savedMessagesId
        if !saved {
            let everyone = clearing
                ? (item.type == .private ? "Очистить у меня и у собеседника" : "Очистить у всех")
                : (item.type == .private ? "Удалить у меня и у собеседника" : "Удалить у всех")
            Button(everyone, role: .destructive) {
                Task {
                    if clearing { await viewModel.confirmClear(forEveryone: true) }
                    else { await viewModel.confirmDelete(forEveryone: true) }
                }
            }
        }
        Button(clearing ? (saved ? "Очистить" : "Очистить только у меня") : (saved ? "Удалить" : "Удалить только у меня"), role: .destructive) {
            Task {
                if clearing { await viewModel.confirmClear(forEveryone: false) }
                else { await viewModel.confirmDelete(forEveryone: false) }
            }
        }
    }
}

/// Найденный на сервере чат, которого нет в списке.
/// В приватном режиме вместо имени «Чат», подпись (ник, число участников) скрыта.
private struct GlobalResultRow: View {
    let result: ChatSearchResult
    @Environment(\.privateMode) private var privateMode

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(title: result.title, id: result.id, url: result.avatarURL, size: OrbitleTheme.smallAvatar)
            VStack(alignment: .leading, spacing: 2) {
                PrivateText(result.title, placeholder: PrivateModeMask.searchResultTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = result.subtitle, !privateMode.isMasked {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !message.time.isEmpty {
                    Text(message.time)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            PrivateText(message.snippet, placeholder: PrivateModeMask.archivePreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
