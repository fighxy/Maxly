import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

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
    /// Мини-приложение бота из строки («Открыть»): тот же запуск, что и из чата с ботом.
    var makeBotApp: ((BotAppRequest) -> MiniAppModel)?
    @State private var botApp: BotAppRequest?
    @State private var composeShown = false
    /// Истории: полоса над чатами и кольца на аватарах личных чатов. `nil` в превью.
    @Environment(StoriesViewModel.self) private var stories: StoriesViewModel?
    /// Настройка приватного режима для плавающей кнопки. `nil` в превью без контейнера.
    @Environment(PrivateModeSettings.self) private var privateModeSettings: PrivateModeSettings?
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Истории спрятаны над поиском: у заголовка — стопка их аватаров. Меняется только на
    /// границе, а не каждый кадр прокрутки.
    @State private var storiesHidden = true
    /// Папки дошли до панели навигации: сверху закреплена их копия.
    @State private var foldersPinned = false
    /// Прокрутка списка прямо из его `UIScrollView`: смещение, палец, инерция.
    @State private var scroll = ChatListScroll()

    var body: some View {
        chatList
        .toolbar { toolbar }
        .onAppear { wireScroll() }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.isSearchActive)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing { editBar }
        }
        .overlay(alignment: .bottomTrailing) { privateModeButton }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(item: $botApp) { request in
            if let makeBotApp {
                MiniAppSheet(model: makeBotApp(request))
            }
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

    // MARK: Шапка

    /// Истории есть: своя или чужие. Без них строки и стопки нет — только кнопка новой истории.
    private var hasStories: Bool {
        guard let stories, selfAvatar != nil, onAddStory != nil else { return false }
        return stories.own != nil || !stories.rings.isEmpty
    }

    /// Шапка — первые строки списка: истории (спрятаны над поиском), поиск,
    /// папки. В поиске нет историй и папок, при правке — историй и поиска.
    private var showsStoriesRow: Bool { hasStories && !viewModel.isSearchActive && !viewModel.isEditing }
    private var showsSearchRow: Bool { !viewModel.isEditing }
    private var showsFolderRow: Bool { viewModel.showsFolders && !viewModel.isSearchActive }
    private var showsStoryStack: Bool { showsStoriesRow && storiesHidden }

    /// Аватары стопки: своя история, затем непросмотренные и просмотренные, как в ленте.
    private var stackRings: [StoryRing] {
        guard let stories else { return [] }
        return [stories.own].compactMap { $0 } + stories.rings
    }

    private var chatList: some View {
        List(selection: listSelection) {
            if showsStoriesRow { storiesRow }
            if showsSearchRow { searchRow }
            if showsFolderRow { folderRow }
            rows
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .environment(\.editMode, .constant(viewModel.isEditing ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .animation(MaxlyMotion.list(viewModel.itemsChange, reduceMotion: reduceMotion), value: viewModel.itemsVersion)
        // Папки, дошедшие до панели навигации, остаются сверху: их копия стоит ровно там, где
        // закрепилась бы строка, на мягком размытии, которое к низу тает без линии.
        .overlay(alignment: .top) {
            if foldersPinned, showsFolderRow {
                folderBar
                    .background { PinnedHeaderBackdrop() }
            }
        }
        // Потянуть список вниз открывает истории, поэтому обновления
        // потягиванием нет: список и так сверяется сам.
    }

    /// Строка шапки: без отступов, разделителей, фона и выбора. Метка внутри сообщает, где строка
    /// лежит в списке.
    private func headerRow<Content: View>(_ id: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background { ChatListProbe(id: id, scroll: scroll) }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
    }

    private var storiesRow: some View {
        headerRow(ChatListScroll.storiesId) {
            if let stories, let selfAvatar, let onAddStory {
                StoriesStrip(stories: stories, selfAvatar: selfAvatar, onAdd: onAddStory)
            }
        }
        // Истории появились (загрузились или вернулись после поиска), а список у самого
        // верха — они прячутся над поиском.
        .onAppear { hideStoriesIfAtTop() }
    }

    private var searchRow: some View {
        headerRow(ChatListScroll.searchId) {
            FlatSearchField(text: $viewModel.searchQuery, isActive: $viewModel.isSearchActive)
                .padding(.horizontal, MaxlyTheme.pad)
                .padding(.vertical, 6)
        }
    }

    private var folderRow: some View {
        headerRow(ChatListScroll.foldersId) { folderBar }
    }

    private var folderBar: some View {
        FolderStrip(tabs: viewModel.folders, selected: viewModel.selectedFolderId) { id in
            viewModel.selectFolder(id)
        }
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var header: ChatListHeaderGeometry {
        scroll.geometry(stories: showsStoriesRow, search: showsSearchRow, folders: showsFolderRow)
    }

    private func wireScroll() {
        scroll.onScroll = { previous, top, dragging, decelerating in
            listScrolled(previous: previous, top: top, dragging: dragging, decelerating: decelerating)
        }
        scroll.onIdle = { listSettled() }
    }

    private func listScrolled(previous: CGFloat, top: CGFloat, dragging: Bool, decelerating: Bool) {
        let header = self.header
        if header.stopsFling(from: previous, to: top, dragging: dragging, decelerating: decelerating),
           let hidden = header.storiesHiddenTop {
            scroll.stop(at: hidden)
            return
        }
        let hidden = header.storiesHidden(at: top)
        if hidden != storiesHidden {
            withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { storiesHidden = hidden }
            if hidden { scroll.revealedByPull = false }
        }
        // Истории вытянуты пальцем целиком: отклик и свежая лента.
        if dragging, !scroll.revealedByPull, let shown = header.storiesShownTop, top <= shown + 1 {
            scroll.revealedByPull = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await stories?.refresh() }
        }
        let pinned = header.foldersPinned(at: top)
        if pinned != foldersPinned { foldersPinned = pinned }
    }

    /// Прокрутка остановилась посреди историй или поиска — доезжает до ближнего края.
    private func listSettled() {
        guard let target = header.snapTarget(at: scroll.top) else { return }
        scroll.scroll(to: target, animated: true)
    }

    private func hideStoriesIfAtTop() {
        Task { @MainActor in
            // Строка историй должна сначала лечь на место.
            try? await Task.sleep(for: .milliseconds(60))
            let header = self.header
            guard !scroll.isInteracting, let shown = header.storiesShownTop, let hidden = header.storiesHiddenTop,
                  scroll.top <= shown + 1 else { return }
            scroll.scroll(to: hidden, animated: false)
        }
    }

    /// Касание стопки или заголовка: истории открываются целиком или прячутся над поиском.
    private func toggleStories() {
        let header = self.header
        if storiesHidden {
            scroll.scroll(to: header.storiesShownTop ?? 0, animated: true)
        } else if let hidden = header.storiesHiddenTop {
            scroll.scroll(to: hidden, animated: true)
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in MaxlyTheme.separatorInset - MaxlyTheme.pad }
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
        EdgeInsets(top: 0, leading: MaxlyTheme.pad, bottom: 0, trailing: MaxlyTheme.pad)
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
        var openApp: (() -> Void)?
        if makeBotApp != nil, let request = viewModel.botApp(for: item) { openApp = { botApp = request } }
        return ChatRow(item: item, storyRing: ring, onStoryTap: openStories, onOpenApp: openApp)
            .tag(item.id)
            .listRowInsets(rowInsets)
            .listRowBackground(item.isPinned ? Color.maxlyPinnedBackground : nil)
            .alignmentGuide(.listRowSeparatorLeading) { _ in MaxlyTheme.separatorInset - MaxlyTheme.pad }
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
            .tint(Color.maxlyAccent)
        } else if viewModel.capabilities.contains(.markUnread) {
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label("Непрочитано", systemImage: "envelope.badge.fill")
            }
            .tint(Color.maxlyAccent)
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
                toggleStories()
            } label: {
                HStack(spacing: 8) {
                    if showsStoryStack {
                        StoryStack(rings: stackRings)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                    if viewModel.connection != .online || viewModel.isCatchingUp {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.navigationTitle).font(.headline)
                }
                .foregroundStyle(.primary)
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: showsStoryStack)
            }
            .buttonStyle(.plain)
            .disabled(!showsStoriesRow)
            .accessibilityLabel(viewModel.navigationTitle)
            .accessibilityHint(showsStoriesRow ? (storiesHidden ? "Показать истории" : "Скрыть истории") : "")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let onAddStory, !viewModel.isSearchActive, !viewModel.isEditing {
                Button(action: onAddStory) {
                    AddStoryGlyph()
                }
                .accessibilityLabel("Новая история")
            }
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
        .padding(.horizontal, MaxlyTheme.pad)
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
                withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { settings.toggle() }
            } label: {
                Image(systemName: settings.isEnabled ? "eye.slash.fill" : "eye")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(settings.isEnabled ? Color.maxlyAccent : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .maxlyGlassCircle(size: 52)
            .padding(.trailing, MaxlyTheme.pad)
            .padding(.bottom, 12)
            .accessibilityLabel(settings.isEnabled ? "Выключить приватный режим" : "Включить приватный режим")
            .transition(.maxlyPop(reduceMotion: reduceMotion))
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

/// Прокрутка списка чатов прямо из его `UIScrollView`.
///
/// Смещение из `onScrollGeometryChange` по-разному учитывает отступы под панели, поэтому
/// смещение, палец и инерция берутся у самого `UIScrollView`, а места строк шапки — у меток в
/// них (`ChatListProbe`), в координатах содержимого. Класс, а не состояние экрана: меняется
/// каждый кадр прокрутки, и экран не должен пересобираться из-за этого.
@MainActor
private final class ChatListScroll {
    static let storiesId = "stories"
    static let searchId = "search"
    static let foldersId = "folders"

    /// Сдвиг прокрутки: прежний и новый верх видимой части, палец, инерция.
    var onScroll: ((_ previous: CGFloat, _ top: CGFloat, _ dragging: Bool, _ decelerating: Bool) -> Void)?
    /// Прокрутка остановилась.
    var onIdle: (() -> Void)?
    /// Истории уже вытянуты пальцем целиком: отклик один раз, пока они снова не спрячутся.
    var revealedByPull = false

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var idleTask: Task<Void, Never>?
    private var lastTop: CGFloat = 0
    private var probes: [String: WeakView] = [:]
    /// Последние известные места строк: строка, ушедшая далеко за экран, переиспользуется.
    private var frames: [String: CGRect] = [:]

    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    /// Верх видимой части в координатах содержимого: `0` — список у самого верха.
    var top: CGFloat {
        guard let scrollView else { return 0 }
        return scrollView.contentOffset.y + scrollView.adjustedContentInset.top
    }

    var isInteracting: Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }

    func attach(_ scroll: UIScrollView) {
        guard scroll !== scrollView else { return }
        scrollView = scroll
        lastTop = top
        // Изменения приходят на главном потоке: их делает UIKit или SwiftUI.
        observation = scroll.observe(\.contentOffset) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.moved(view) }
        }
    }

    func register(_ view: UIView, id: String) {
        probes[id] = WeakView(view)
    }

    func geometry(stories: Bool, search: Bool, folders: Bool) -> ChatListHeaderGeometry {
        ChatListHeaderGeometry(
            stories: stories ? range(Self.storiesId) : nil,
            search: search ? range(Self.searchId) : nil,
            folders: folders ? frame(Self.foldersId)?.minY : nil
        )
    }

    /// Доехать до `target` (верх видимой части в координатах содержимого).
    func scroll(to target: CGFloat, animated: Bool) {
        guard let scroll = scrollView else { return }
        let insets = scroll.adjustedContentInset
        let maxY = max(-insets.top, scroll.contentSize.height + insets.bottom - scroll.bounds.height)
        let y = min(max(target - insets.top, -insets.top), maxY)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: animated)
    }

    /// Остановить инерцию и встать на `target`.
    func stop(at target: CGFloat) {
        guard let scroll = scrollView else { return }
        scroll.setContentOffset(scroll.contentOffset, animated: false)
        self.scroll(to: target, animated: false)
    }

    private func range(_ id: String) -> ClosedRange<CGFloat>? {
        frame(id).map { $0.minY...$0.maxY }
    }

    private func frame(_ id: String) -> CGRect? {
        if let view = probes[id]?.view, let scroll = scrollView, view.window != nil, view.isDescendant(of: scroll) {
            let frame = view.convert(view.bounds, to: scroll)
            frames[id] = frame
            return frame
        }
        return frames[id]
    }

    private func moved(_ scroll: UIScrollView) {
        let now = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let previous = lastTop
        lastTop = now
        onScroll?(previous, now, scroll.isTracking || scroll.isDragging, scroll.isDecelerating)
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, !self.isInteracting else { return }
            self.onIdle?()
        }
    }
}

/// Метка в строке шапки: находит `UIScrollView` списка и сообщает, где лежит строка.
private struct ChatListProbe: UIViewRepresentable {
    let id: String
    let scroll: ChatListScroll

    func makeUIView(context: Context) -> ProbeView { ProbeView(id: id, scroll: scroll) }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private let id: String
        private let scroll: ChatListScroll

        init(id: String, scroll: ChatListScroll) {
            self.id = id
            self.scroll = scroll
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            scroll.register(self, id: id)
            var view = superview
            while let current = view {
                if let list = current as? UIScrollView {
                    scroll.attach(list)
                    return
                }
                view = current.superview
            }
        }
    }
}

/// Подложка закреплённых папок: размытие под панелью навигации и под капсулой, которое к
/// низу тает, а не обрывается линией.
private struct PinnedHeaderBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.bar)
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .padding(.bottom, -16)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

/// Значок новой истории: пунктирный круг с плюсом.
private struct AddStoryGlyph: View {
    var body: some View {
        ZStack {
            Image(systemName: "circle.dashed")
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
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
            AvatarView(title: result.title, id: result.id, url: result.avatarURL, size: MaxlyTheme.smallAvatar)
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
