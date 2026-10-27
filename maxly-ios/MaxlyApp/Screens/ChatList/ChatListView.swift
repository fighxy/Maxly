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
    /// Играющее голосовое: плеер прилипает к папкам, без папок висит под шапкой отдельно.
    /// `nil`, когда плеер показывает открытый чат.
    var nowPlaying: VoiceNowPlaying?
    var onOpenVoice: (VoiceNowPlaying.Track) -> Void = { _ in }
    /// Экран «Папки» для «Настроить папки» и «Изменить порядок» из меню вкладки; `nil` — их нет.
    var makeFoldersModel: (() -> FoldersModel)?
    /// Меню вкладки папки: выбор чатов (с названием — «Настроить папку»), удаление, экран папок.
    @State private var folderEdit: FolderEdit?
    @State private var folderDelete: ServerFolder?
    @State private var foldersScreen: FoldersScreenRequest?
    @State private var botApp: BotAppRequest?
    @State private var composeShown = false
    /// «Заблокировать» из меню ждёт подтверждения.
    @State private var blockCandidate: ChatListItem?
    /// Бот: «Остановить» и «Удалить и остановить» ждут подтверждения, жалоба — выбора причины.
    @State private var botStopCandidate: ChatListItem?
    @State private var botDeleteCandidate: ChatListItem?
    @State private var botReport: BotReport?
    /// «Создать папку» из меню строки: для какого чата.
    @State private var newFolderChat: String?
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
        // Части отдельно: одно выражение со всеми окнами компилятор не успевал проверить.
        screen
            .modifier(ChatListRowDialogs(
                viewModel: viewModel,
                blockCandidate: $blockCandidate,
                botStopCandidate: $botStopCandidate,
                botDeleteCandidate: $botDeleteCandidate,
                botReport: $botReport
            ))
            .createFolderAlert(for: $newFolderChat) { chatId, title in
                Task { await viewModel.createFolder(chatId: chatId, title: title) }
            }
            .overlay(alignment: .top) { noticeBanner }
    }

    private var screen: some View {
        chatList
        .modifier(ChatListFolderSheets(
            viewModel: viewModel,
            makeFoldersModel: makeFoldersModel,
            folderEdit: $folderEdit,
            foldersScreen: $foldersScreen,
            folderDelete: $folderDelete
        ))
        .toolbar { toolbar }
        .onAppear { wireScroll() }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.isSearchActive)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isEditing { editBar }
        }
        .safeAreaInset(edge: .top, spacing: 0) { standalonePlayer }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: isPlaying)
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
                NewChatSheet(
                    model: newChat,
                    onOpened: { opened in
                        newChat.consumeOpened()
                        composeShown = false
                        onOpened(opened)
                    },
                    shareTargets: { viewModel.items }
                )
                .task {
                    newChat.show()
                    newChat.activate()
                }
            } else {
                ComposeSheet()
            }
        }
        .modifier(ChatListEraseDialogs(viewModel: viewModel))
    }

    /// Итог действия из меню строки («Чат добавлен в «Работа»», ошибка): гаснет сам.
    @ViewBuilder
    private var noticeBanner: some View {
        if let text = viewModel.notice {
            Text(text)
                .font(.app(.subheadline))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { viewModel.notice = nil }
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2.5))
                    if viewModel.notice == text { viewModel.notice = nil }
                }
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
        Group {
            if let nowPlaying, isPlaying {
                // Плеер — нижняя секция той же стеклянной карточки, что и папки.
                TopDock {
                    folderStrip(glass: false)
                    TopDockDivider()
                    VoicePlayerRow(model: nowPlaying, onOpen: onOpenVoice)
                }
            } else {
                folderStrip(glass: true)
            }
        }
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func folderStrip(glass: Bool) -> some View {
        FolderStrip(
            tabs: viewModel.folders,
            selected: viewModel.selectedFolderId,
            glass: glass,
            menu: { tab in folderMenu(tab.id) }
        ) { id in
            viewModel.selectFolder(id)
        }
    }

    // MARK: Меню вкладки папки

    private func folderMenu(_ id: String) -> AnyView? {
        let entries = viewModel.folderMenu(id)
        guard !entries.isEmpty else { return nil }
        return AnyView(FolderTabMenuItems(entries: entries) { pickFolder(id, $0) })
    }

    private func pickFolder(_ id: String, _ entry: FolderTabMenu.Entry) {
        switch entry {
        case .editFolders: foldersScreen = FoldersScreenRequest(editing: false)
        case .reorder: foldersScreen = FoldersScreenRequest(editing: true)
        case .editFolder: folderEdit = FolderEdit(id: id, withTitle: true)
        case .addChats: folderEdit = FolderEdit(id: id, withTitle: false)
        case .readAll: Task { await viewModel.readFolder(id) }
        case .mute(let muted): Task { await viewModel.setFolderMuted(id, muted: !muted) }
        case .delete: folderDelete = viewModel.serverFolder(id)
        }
    }

    private var isPlaying: Bool { nowPlaying?.track != nil }

    /// Папок нет (или идёт поиск): плеер — отдельная карточка чуть ниже шапки.
    @ViewBuilder
    private var standalonePlayer: some View {
        if let nowPlaying, isPlaying, !showsFolderRow {
            TopDock {
                VoicePlayerRow(model: nowPlaying, onOpen: onOpenVoice)
            }
            .padding(.horizontal, MaxlyTheme.pad)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .transition(.maxlyBar(edge: .top, reduceMotion: reduceMotion))
        }
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
            ChatListSearchResults(viewModel: viewModel, selection: $selection, rowInsets: rowInsets, onOpenMessage: onOpenMessage)
        } else {
            placeholder
                .listRowSeparator(.hidden)
                .selectionDisabled()
            if let message = viewModel.inlineError {
                Button {
                    viewModel.dismissError()
                } label: {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.app(.footnote))
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
            // Остановлен ли бот (чёрный список спрашивается раз за сеанс): меню знает до открытия.
            .task(id: item.id) { if ChatListMenu.isBot(item) { await viewModel.prepareMenu(chatId: item.id) } }
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

    /// Меню строки в порядке Max (`ChatListMenu.entries`). «Открыть» и архив остались в
    /// касании и свайпе.
    @ViewBuilder
    private func menu(_ item: ChatListItem) -> some View {
        let match = storyMatch(item)
        let ring = match.flatMap { stories?.ring(of: $0.id, kind: $0.kind) }
        let isOwnRing = ring != nil && ring?.owner == stories?.own?.owner
        let entries = ChatListMenu.entries(
            item: item,
            folders: viewModel.folderChoices(chatId: item.id),
            capabilities: viewModel.capabilities,
            hasStories: ring != nil && !isOwnRing,
            canBlock: viewModel.canBlock,
            botStopped: viewModel.isBotStopped(chatId: item.id)
        )
        ForEach(entries, id: \.self) { entry in
            menuEntry(entry, item: item, ring: ring)
        }
    }

    @ViewBuilder
    private func menuEntry(_ entry: ChatListMenu.Entry, item: ChatListItem, ring: StoryRing?) -> some View {
        switch entry {
        case .folders(let folders):
            FolderMenu(
                folders: folders,
                onToggle: { id in Task { await viewModel.toggleFolder(chatId: item.id, folderId: id) } },
                onCreate: { newFolderChat = item.id }
            )
        case .pin(let pinned):
            Button { Task { await viewModel.togglePin(chatId: item.id) } } label: {
                Label(entry.title, systemImage: pinned ? "pin.slash" : "pin")
            }
        case .read(let unread):
            Button { Task { await viewModel.toggleRead(chatId: item.id) } } label: {
                Label(entry.title, systemImage: unread ? "envelope.open" : "envelope.badge")
            }
        case .mute(let muted):
            if muted {
                Button { Task { await viewModel.toggleMute(chatId: item.id) } } label: {
                    Label(entry.title, systemImage: "bell")
                }
            } else {
                Menu {
                    ForEach(ChatListMenu.MuteFor.allCases, id: \.self) { choice in
                        Button(role: choice.isDanger ? .destructive : nil) {
                            Task { await viewModel.muteFor(chatId: item.id, choice) }
                        } label: {
                            Text(choice.title)
                        }
                    }
                } label: {
                    Label(entry.title, systemImage: "bell.slash")
                }
            }
        case .erase:
            Button { viewModel.requestClear(chatId: item.id) } label: {
                Label(entry.title, systemImage: "eraser")
            }
        case .hideStories:
            Button {
                guard let ring else { return }
                Task { await stories?.hideOwner(ring.owner, name: ring.name) }
            } label: {
                Label(entry.title, systemImage: "eye.slash")
            }
        case .block:
            Button(role: .destructive) { blockCandidate = item } label: {
                Label(entry.title, systemImage: "hand.raised")
            }
        case .report:
            Button(role: .destructive) {
                Task {
                    let reasons = await viewModel.botReportReasons(chatId: item.id)
                    if reasons.isEmpty { viewModel.notice = "Не удалось загрузить причины жалобы" } else { botReport = BotReport(item: item, reasons: reasons) }
                }
            } label: {
                Label(entry.title, systemImage: "exclamationmark.circle")
            }
        case .stopBot(let stopped):
            if stopped {
                Button { Task { await viewModel.restartBot(chatId: item.id) } } label: {
                    Label(entry.title, systemImage: "play.circle")
                }
            } else {
                Button(role: .destructive) { botStopCandidate = item } label: {
                    Label(entry.title, systemImage: "minus.circle")
                }
            }
        case .deleteAndStop:
            Button(role: .destructive) { botDeleteCandidate = item } label: {
                Label(entry.title, systemImage: "trash")
            }
        case .delete:
            Button(role: .destructive) { viewModel.requestDelete(chatId: item.id) } label: {
                Label(entry.title, systemImage: "trash")
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
                    Text(viewModel.navigationTitle).font(.app(.headline))
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

    /// Нижняя панель правки: «Прочитать», «В архив», «Удалить». Без выбора «Прочитать все»
    /// читает всю папку, а архив и удаление ждут выбора; над ними — подсказка про порядок
    /// закреплённых.
    private var editBar: some View {
        let archivable = viewModel.archivableSelection.count
        let deletable = viewModel.deletableSelection.count
        return VStack(spacing: 8) {
            if viewModel.editSelection.isEmpty, viewModel.capabilities.contains(.reorderPins), viewModel.pinnedCount > 1 {
                Text("Перетащите закреплённые, чтобы поменять порядок")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button(viewModel.editSelection.isEmpty ? "Прочитать все" : "Прочитать") {
                    Task { await viewModel.readSelected() }
                }
                .disabled(!canRead)
                .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.capabilities.contains(.archive) {
                    Button(archivable > 1 ? "В архив (\(archivable))" : "В архив") {
                        Task { await viewModel.archiveSelected() }
                    }
                    .disabled(archivable == 0)
                    .frame(maxWidth: .infinity)
                }
                if viewModel.capabilities.contains(.delete) {
                    Button(deletable > 1 ? "Удалить (\(deletable))" : "Удалить", role: .destructive) {
                        viewModel.requestDeleteSelected()
                    }
                    .foregroundStyle(deletable == 0 ? Color.secondary : Color.red)
                    .disabled(deletable == 0)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.editSelection.isEmpty)
    }

    /// «Прочитать все» — есть непрочитанные в папке; «Прочитать» — среди выбранных есть
    /// непрочитанные.
    private var canRead: Bool {
        if viewModel.editSelection.isEmpty {
            return viewModel.tabBadge > 0 || viewModel.items.contains { $0.badge != nil }
        }
        return viewModel.items.contains { viewModel.editSelection.contains($0.id) && $0.badge != nil }
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
}
