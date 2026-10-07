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
    /// Полоса скрыта жестом. Общее для аккаунтов на этом устройстве.
    @AppStorage("stories.stripCollapsed") private var storiesCollapsed = false
    @State private var stripReveal: CGFloat = 1
    @State private var stripReady = false
    @State private var draggingStrip = false
    /// Край списка на старте жеста: к концу жест уже мог сдвинуть список.
    @State private var dragAtTop = true
    @GestureState private var stripGestureLive = false
    @State private var stripHeight: CGFloat = 96
    @State private var listAtTop = true

    var body: some View {
        VStack(spacing: 0) {
            storyStrip
            chatChrome
            chatList
        }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.isSearchActive)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing { editBar }
        }
        .overlay(alignment: .bottomTrailing) { privateModeButton }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear {
            guard !stripReady else { return }
            stripReveal = storiesCollapsed ? 0 : 1
            stripReady = true
        }
        .onChange(of: stripGestureLive) { _, live in
            // `onEnded` успевает зафиксировать жест в этом же кадре. Отмена — только если он ещё висит.
            guard !live else { return }
            Task { @MainActor in
                if draggingStrip { cancelStripDrag() }
            }
        }
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

    /// Истории над поиском и папками. Поиск и правка списка прячут полосу, не забывая жест.
    @ViewBuilder
    private var storyStrip: some View {
        if let stories, let selfAvatar, let onAddStory, showsStoryStrip {
            let reveal = stripReady ? stripReveal : (storiesCollapsed ? 0 : 1)
            let strip = StoriesStrip(stories: stories, selfAvatar: selfAvatar, onAdd: onAddStory)
            ZStack(alignment: .bottom) {
                // Высота без обрезки: иначе измерение схлопывается вместе с полосой.
                strip
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: StripHeightKey.self, value: geo.size.height)
                        }
                    }
                strip
                    .frame(maxWidth: .infinity)
            }
            .onPreferenceChange(StripHeightKey.self) { height in
                // Обрезанный кадр не уменьшает замер: иначе закрытая полоса забывает свою высоту.
                if height > stripHeight { stripHeight = height }
            }
            .frame(height: max(0, stripHeight * reveal), alignment: .bottom)
            .clipped()
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(stripDrag(header: true))
            .accessibilityHint(storiesCollapsed ? "Потяните вниз, чтобы показать истории" : "Потяните вверх, чтобы скрыть истории")
        }
    }

    private var showsStoryStrip: Bool {
        !viewModel.isSearchActive && !viewModel.isEditing
    }

    private var chatChrome: some View {
        VStack(spacing: 0) {
            FlatSearchField(text: $viewModel.searchQuery, isActive: $viewModel.isSearchActive)
                .padding(.horizontal, OrbitleTheme.pad)
                .padding(.top, 4)
                .padding(.bottom, viewModel.showsFolders && !viewModel.isSearchActive ? 0 : 8)
            if viewModel.showsFolders, !viewModel.isSearchActive {
                FolderSegments(tabs: viewModel.folders, selected: viewModel.selectedFolderId) { id in
                    viewModel.selectFolder(id)
                }
            }
        }
        .simultaneousGesture(stripDrag(header: true))
    }

    private var chatList: some View {
        List(selection: listSelection) { rows }
            .listStyle(.plain)
            .coordinateSpace(name: "chat-list")
            .environment(\.editMode, .constant(viewModel.isEditing ? .active : .inactive))
            .animation(OrbitleMotion.list(viewModel.itemsChange, reduceMotion: reduceMotion), value: viewModel.itemsVersion)
            .simultaneousGesture(stripDrag(header: false))
            .modifier(StoryListRefresh(enabled: viewModel.isSearchActive || !storiesCollapsed) {
                await viewModel.refresh()
                await stories?.refresh()
            })
            .overlay { placeholder.animation(OrbitleMotion.fade, value: viewModel.content) }
    }

    /// Поднятие от верхнего края прячет полосу. Потянуть вниз возвращает её.
    /// Обновление списка — следующее потягивание, когда полоса уже открыта.
    private func stripDrag(header: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($stripGestureLive) { _, state, _ in state = true }
            .onChanged { value in
                guard showsStoryStrip else { return }
                if !draggingStrip { dragAtTop = header || listAtTop }
                let drag = value.translation.height
                let next = StoryStripMotion.reveal(expanded: !storiesCollapsed, drag: drag, height: stripHeight, atTop: dragAtTop)
                let moved = abs(next - (storiesCollapsed ? 0 : 1)) > 0.001
                guard moved || draggingStrip else { return }
                draggingStrip = true
                if reduceMotion {
                    let open = StoryStripMotion.settledExpanded(wasExpanded: !storiesCollapsed, drag: drag, atTop: dragAtTop, threshold: StoryStripMotion.threshold)
                    stripReveal = open ? 1 : 0
                } else {
                    stripReveal = next
                }
            }
            .onEnded { value in
                guard draggingStrip else { return }
                finishStripDrag(drag: value.translation.height)
            }
    }

    /// Отмена жеста не вызывает `onEnded`: полоса возвращается к запомненному положению.
    private func cancelStripDrag() {
        guard draggingStrip else { return }
        draggingStrip = false
        stripReveal = storiesCollapsed ? 0 : 1
    }

    private func finishStripDrag(drag: CGFloat) {
        let open = StoryStripMotion.settledExpanded(
            wasExpanded: !storiesCollapsed,
            drag: drag,
            atTop: dragAtTop,
            threshold: StoryStripMotion.threshold
        )
        draggingStrip = false
        storiesCollapsed = !open
        if reduceMotion {
            stripReveal = open ? 1 : 0
        } else {
            withAnimation(.snappy(duration: 0.22)) { stripReveal = open ? 1 : 0 }
        }
    }

    @ViewBuilder
    private var rows: some View {
        Color.clear.frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: ListTopKey.self, value: geo.frame(in: .named("chat-list")).minY)
                }
            }
            .onPreferenceChange(ListTopKey.self) { minY in
                listAtTop = minY >= -2
            }
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
        if let match, let stories { openStories = { stories.open(match.id) } }
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
                            .foregroundStyle(Color.orbitleAccent)
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
            if !search.messages.isEmpty {
                Section("Сообщения") {
                    // Чат открывается на самом сообщении: модель чата запоминает его до открытия.
                    ForEach(search.messages) { message in
                        Button {
                            onOpenMessage(message)
                            selection = message.chatId
                        } label: {
                            FoundMessageRow(message: message)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

/// Обновление списка есть, только когда полоса уже открыта. Иначе жест вниз её показывает.
private struct StoryListRefresh: ViewModifier {
    let enabled: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

private struct StripHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ListTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
