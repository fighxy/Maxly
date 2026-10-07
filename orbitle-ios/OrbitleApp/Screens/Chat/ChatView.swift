import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var title: String
    /// Комментарии канала: `true` включены, `false` выключены, `nil` сервер не сказал —
    /// тогда кнопка есть только у постов, к которым сервер прислал счётчик.
    var commentsEnabled: Bool?
    /// В группе у чужих сообщений видны имя и аватар автора, в личном чате и канале — нет.
    var chatType: ChatType = .private
    /// Чаты для пересылки (без текущего).
    var forwardTargets: () -> [ChatListItem] = { [] }
    /// Можно ли писать. Нет — вместо поля ввода плашка (в канале — уведомления).
    /// `nil` — чата нет в списке (открыт из поиска или по ссылке): решает карточка чата.
    var canWrite: Bool? = true
    var isMuted = false
    var onToggleMute: (() -> Void)?
    /// Контакты для вкладки «Контакт» листа вложений. `nil` — вкладка пустая.
    var contactList: (() -> AsyncStream<[Contact]>)? = nil
    /// Панель эмодзи и стикеров (одна на приложение: каталог грузится раз).
    var stickerPanel: StickerPanelModel? = nil
    /// Сеть, «печатает…», звук и галочка — живые данные из списка чатов для шапки.
    var live: () -> ChatHeaderLive = { ChatHeaderLive() }
    /// Модель профиля чата: шапка берёт из неё статус, нажатие на шапку открывает профиль.
    var makeProfile: (() -> ChatProfileViewModel?)?
    /// Управление группой или каналом. `nil` — до входа ядра.
    var chatAdmin: (any ChatAdminRepository)? = nil
    /// Очистка переписки или удаление чата из профиля. Первый флаг — очистка, второй — у всех.
    var onEraseChat: ((Bool, Bool) -> Void)? = nil
    /// Выйти из группы или отписаться от канала из профиля.
    var onLeave: (() -> Void)? = nil
    /// Открыть другой чат из профиля (общий чат собеседника).
    var onOpenChat: ((String) -> Void)? = nil
    /// Пометка «непрочитано» с сообщения, отправленного в эту дату. Экран закрывает тот, кто
    /// открыл чат, когда сервер принял пометку.
    var onMarkUnread: ((Date) -> Void)? = nil
    /// Эмодзи двойного нажатия. `nil` — сервер выключил быструю реакцию.
    var quickReaction: String? = nil
    /// Мини-приложение бота: кнопка «Открыть приложение» и inline-кнопки `OPEN_APP`.
    var makeBotApp: ((BotAppRequest) -> MiniAppModel)? = nil
    /// Позвонить собеседнику личного чата (из профиля): аудио или видео.
    var onCall: ((CallCenter.Peer, Bool) -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var profile: ChatProfileViewModel?
    @State private var profileShown = false
    @State private var forwardList: [ChatListItem] = []
    @State private var attachmentsShown = false
    @State private var panelShown = false
    /// Высота последней клавиатуры без нижнего отступа: панель встаёт на её место.
    @State private var keyboardHeight: CGFloat = 300
    @State private var searchShown = false
    @State private var pollShown = false
    @State private var scheduleShown = false
    @State private var searchQuery = ""
    @State private var pollTitle = ""
    @State private var pollFirst = ""
    @State private var pollSecond = ""
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    /// Верх нижних кнопок на экране, для мягкого размытия низа ленты.
    @State private var bottomControlsTop: CGFloat = 0
    /// Обои из «Оформления» и где они лежат на экране (для перехода в них у низа ленты).
    @Environment(\.chatWallpaper) private var wallpaper
    @State private var wallpaperFrame: CGRect = .zero
    @State private var recording = RecordingSession()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Приватный режим: пузыри закрыты заглушкой или размытием, касание открывает на время.
    @Environment(\.privateMode) private var privateMode
    @Environment(PrivateModeSettings.self) private var privateModeSettings: PrivateModeSettings?
    /// Истории собеседника: кольцо на аватаре шапки, касание открывает их.
    @Environment(StoriesViewModel.self) private var stories: StoriesViewModel?
    @State private var reveal = PrivateModeReveal()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Тело собрано из слоёв: одна длинная цепочка модификаторов не укладывается
    // в лимит проверки типов компилятора. Порядок модификаторов прежний.
    var body: some View {
        chatEvents
    }

    /// Лента с обоями, верхними плашками, полем ввода и панелью стикеров.
    private var transcriptLayer: some View {
        ChatTranscript(
            viewModel: viewModel,
            chatType: kind,
            commentsEnabled: comments,
            canWrite: writable,
            reveal: reveal,
            focus: $composerFocused,
            bottomControlsTop: bottomControlsTop,
            wallpaperFrame: wallpaperFrame,
            quickReaction: quickReaction
        )
        // Обои за лентой: на весь экран, под шапкой, полем ввода и клавиатурой, не
        // прокручиваются с сообщениями.
        .background {
            ChatWallpaperBackground(wallpaper: wallpaper)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { wallpaperFrame = $0 }
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBanners }
        // Режим включают и выключают и с другого экрана: капсула всё равно выезжает плавно.
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: privateMode)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
        .onChange(of: composerFocused) { _, focused in
            // Клавиатура вернулась — панель уходит под неё без анимации: место то же.
            if focused, panelShown { panelShown = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let bottom = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
                .first ?? 0
            let height = frame.height - bottom
            // Плавающая и внешняя клавиатуры низкие: панель остаётся обычной высоты.
            if height > 200 { keyboardHeight = height }
        }
    }

    private var topBanners: some View {
        VStack(spacing: 0) {
            if privateMode.isMasked { privateModeBanner }
            if let pinned = viewModel.pinned {
                pinBanner(id: pinned.id, text: pinned.text)
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            ChatComposer(
                viewModel: viewModel,
                recording: recording,
                focus: $composerFocused,
                attachmentsShown: $attachmentsShown,
                panelShown: $panelShown,
                canWrite: writable,
                showsReadOnlyBar: canWrite != nil || profile?.profile != nil,
                chatType: kind,
                isMuted: isMuted,
                // Звук чата вне списка не переключить: его нет среди чатов аккаунта.
                onToggleMute: canWrite == nil ? nil : onToggleMute,
                onOpenApp: openAppAction,
                join: joinAction,
                onSearch: kind == .channel && onToggleMute != nil && canWrite != nil ? { searchShown = true } : nil
            )
            if panelShown, writable, let stickerPanel {
                StickerPanel(
                    model: stickerPanel,
                    height: keyboardHeight,
                    onEmoji: { viewModel.insertEmoji($0.emoji, animated: $0.animated) },
                    onBackspace: { viewModel.deleteBackward() },
                    onSticker: { sticker in Task { await viewModel.sendSticker(sticker) } }
                )
                .transition(.move(edge: .bottom))
            }
        }
        // Верх поля ввода — от него лента тает в фон к низу экрана (`ChatBottomBlur`).
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { bottomControlsTop = $0 }
    }

    /// Шапка, переход в профиль и загрузка карточки чата.
    private var navigationLayer: some View {
        transcriptLayer
            // Видимость tab bar управляется стабильным MainTabView.
            // Системный заголовок (и подпись кнопки «назад» следующего экрана) размыть нельзя:
            // в приватном режиме там всегда общее «Личный чат» / «Групповой чат».
            .navigationTitle(shownTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { headerToolbar }
            // Стеклянная капсула названия над лентой, под статус-баром мягкое размытие.
            .chatHeaderBlur()
            .navigationDestination(isPresented: $profileShown) { profileDestination }
            .task {
                // Шапка: статус и аватар из карточки чата, она же открывается профилем.
                if profile == nil { profile = makeProfile?() }
                // Возврат из профиля тоже запускает эту задачу: свежую карточку не перезапрашиваем.
                await profile?.loadIfStale()
                viewModel.notePeer(profile?.shown.peerId, isBot: profile?.shown.kind == .bot)
                await stories?.loadRing(storyOwner, kind: storyKind)
                // Общие медиа из кэша — заранее, чтобы профиль открылся с ними. Пауза: сначала лента.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let card = profile else { return }
                await card.updateShared(viewModel.messages, currentUserId: viewModel.currentUserId) {
                    await viewModel.sharedHistory()
                }
            }
    }

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button(action: openProfile) {
                ChatHeaderTitle(
                    title: headerTitle,
                    maskedTitle: maskedTitle,
                    status: privateMode.isMasked ? .none : headerStatus,
                    isVerified: live().isVerified || profile?.isOfficial == true,
                    isMuted: isMuted
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shownTitle), открыть профиль")
        }
        // Поиск, опрос, отложенная отправка и звонки — в профиле чата: справа в шапке
        // только аватар.
        // Слот существует с первого кадра: загрузка профиля не перестраивает toolbar.
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: openAvatar) {
                headerAvatar
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Профиль")
            .transaction { $0.animation = nil }
        }
    }

    /// Касание аватара в шапке: истории собеседника, если есть, иначе профиль.
    private func openAvatar() {
        if let owner = storyOwner, stories?.ring(of: owner, kind: storyKind) != nil {
            stories?.open(owner)
        } else {
            openProfile()
        }
    }

    @ViewBuilder
    private var profileDestination: some View {
        if let profile {
            ChatProfileView(
                viewModel: profile,
                chatAdmin: chatAdmin,
                contactList: contactList,
                context: profileContext(for: profile),
                live: live()
            )
            // Профиль открывают осознанно, и приватный режим его не прячет.
            .environment(\.privateMode, .visible)
        }
    }

    /// Листы: комментарии, реакции, поиск, опрос, отложенная отправка, мини-приложение, вложения.
    private var sheetsLayer: some View {
        navigationLayer
            .sheet(item: $viewModel.openedComments, onDismiss: { viewModel.closeComments() }) { post in
                if let model = viewModel.commentsModel(for: post) {
                    CommentsView(model: model, onClose: { viewModel.closeComments() }, onBlockAuthor: { comment in
                        guard let chatAdmin else { throw OrbitleError.rejected("Управление чатом недоступно") }
                        let messageId = comment.serverId ?? comment.id
                        try await chatAdmin.blockCommentAuthor(
                            chatId: viewModel.chatId,
                            postId: model.postId,
                            userId: comment.authorId,
                            messageId: messageId
                        )
                    })
                        .presentationDragIndicator(.visible)
                        // В листе комментариев обоев нет: пузыри обычные.
                        .environment(\.chatWallpaper, .plain)
                }
            }
            .sheet(item: $viewModel.reactionPickerTarget) { message in
                ReactionPicker(
                    catalog: viewModel.reactionCatalog,
                    mine: message.content.reactions.mine,
                    onPick: { emoji in Task { await viewModel.pickReaction(emoji) } },
                    onClose: { viewModel.reactionPickerTarget = nil }
                )
                .environment(\.privateMode, .visible)
            }
            .sheet(isPresented: $searchShown) { searchSheet }
            .sheet(isPresented: $pollShown) { pollSheet }
            .sheet(isPresented: $scheduleShown) { scheduleSheet }
            .sheet(item: $viewModel.botAppRequest) { request in
                if let makeBotApp {
                    MiniAppSheet(model: makeBotApp(request))
                        .environment(\.privateMode, .visible)
                }
            }
            .onChange(of: viewModel.openURLRequest) { _, url in
                guard let url else { return }
                viewModel.openURLRequest = nil
                openURL(url)
            }
            .sheet(isPresented: $attachmentsShown) { attachmentSheet }
            .sheet(item: $viewModel.reactionUsers) { model in
                // Открывается из открытого пузыря — значит, смотреть его хотят.
                ReactionUsersView(model: model) { viewModel.reactionUsers = nil }
                    .environment(\.privateMode, .visible)
            }
    }

    private var searchSheet: some View {
        NavigationStack {
            List(viewModel.searchHits, id: \.messageId) { hit in
                Button {
                    searchShown = false
                    viewModel.focusReply(hit.messageId, at: hit.date)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.text.isEmpty ? "Сообщение" : hit.text).lineLimit(2)
                        if let date = hit.date {
                            Text(ChatContentFormat.time(date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "В этом чате")
            .onSubmit(of: .search) { Task { await viewModel.searchInChat(searchQuery) } }
            .overlay { if viewModel.searchBusy { ProgressView() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { searchShown = false } }
            }
        }
    }

    private var pollSheet: some View {
        NavigationStack {
            Form {
                TextField("Вопрос", text: $pollTitle)
                TextField("Ответ 1", text: $pollFirst)
                TextField("Ответ 2", text: $pollSecond)
            }
            .navigationTitle("Опрос")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { pollShown = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        pollShown = false
                        Task { await viewModel.sendPoll(title: pollTitle, answers: [pollFirst, pollSecond]) }
                    }
                    .disabled(!pollReady)
                }
            }
        }
    }

    /// Опрос уходит, когда заполнены оба ответа.
    private var pollReady: Bool {
        let first = pollFirst.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = pollSecond.trimmingCharacters(in: .whitespacesAndNewlines)
        return !first.isEmpty && !second.isEmpty
    }

    private var scheduleSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Когда", selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("Отправить позже")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { scheduleShown = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Запланировать") {
                        scheduleShown = false
                        Task { await viewModel.schedule(text: viewModel.draft, at: scheduleDate) }
                    }
                    .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var attachmentSheet: some View {
        AttachmentSheet(
            contactList: contactList,
            onSend: { drafts, caption in
                attachmentsShown = false
                Task { await viewModel.sendAttachments(drafts, caption: caption) }
            },
            onClose: { attachmentsShown = false }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Лист вложений — своя галерея и контакты, выбор идёт осознанно.
        .environment(\.privateMode, .visible)
    }

    /// Полноэкранный просмотр медиа и файлов, видеосообщение и жизненный цикл экрана.
    private var coversLayer: some View {
        sheetsLayer
            .fullScreenCover(item: unlessProfileShown($viewModel.viewer)) { request in
                MediaViewer(
                    request: request,
                    download: { await viewModel.downloadVideo($0) },
                    notice: viewModel.notice,
                    isSaving: viewModel.isSaving,
                    onSave: { viewModel.saveViewerSlide($0, to: $1) }
                ) { viewModel.viewer = nil }
                    .fileExportSheet(viewModel, fromViewer: true)
                    .environment(\.privateMode, .visible)
            }
            .fileExportSheet(viewModel, fromViewer: false)
            .fullScreenCover(item: unlessProfileShown($viewModel.openedFile)) { file in
                FileQuickLook(url: file.url, title: file.name) { viewModel.openedFile = nil }
                    .environment(\.privateMode, .visible)
            }
            .overlay {
                if recording.isVideo {
                    VideoNoteOverlay(session: recording)
                }
            }
            .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: recording.isVideo)
            .modifier(ChatHistoryLifecycle(model: viewModel, requestsComments: wantsCommentCounts))
    }

    /// Пока открыт профиль, просмотр из ленты не показывается: его показывает профиль.
    private func unlessProfileShown<Item>(_ item: Binding<Item?>) -> Binding<Item?> {
        profileShown ? .constant(nil) : item
    }

    private var lifecycleLayer: some View {
        coversLayer
            .onAppear {
                recording.onStart = { [viewModel] in viewModel.stopVoice() }
                recording.onRecorded = { [viewModel] draft in
                    Task { await viewModel.sendAttachments([draft], caption: "") }
                }
            }
            .onDisappear {
                panelShown = false
                recording.cancel()
                reveal.hideAll()
            }
            // Режим выключили или сменили вид — открытые пузыри снова закрыты при следующем включении.
            .onChange(of: privateMode) { _, _ in reveal.hideAll() }
            .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.notice)
    }

    /// Удаление и пересылка сообщения, ответ, правка, пометка «непрочитано» и фаза приложения.
    private var chatEvents: some View {
        lifecycleLayer
            // Окно по центру: на iOS 26 confirmationDialog всплывает облаком от вида, к которому
            // привязан, — у шапки, далеко от выбранного сообщения.
            .alert(
                "Удалить сообщение?",
                isPresented: deletionShown,
                presenting: viewModel.deletionCandidate
            ) { message in
                deletionActions(message)
            }
            .sheet(isPresented: forwardShown) {
                ForwardPickerView(
                    targets: forwardList,
                    onPick: { id in Task { await viewModel.forward(to: id) } },
                    onCancel: { viewModel.forwardCandidate = nil }
                )
            }
            .onChange(of: viewModel.forwardCandidate?.id) { _, id in
                if id != nil { forwardList = forwardTargets() }
            }
            .onChange(of: viewModel.unreadMarkCandidate?.id) { _, id in
                guard id != nil, let message = viewModel.unreadMarkCandidate else { return }
                viewModel.unreadMarkCandidate = nil
                onMarkUnread?(message.timestamp)
            }
            // Выбрали сообщение для ответа — клавиатура сразу открывается.
            .onChange(of: viewModel.replyTarget?.id) { _, id in
                if id != nil { composerFocused = true }
            }
            .onChange(of: viewModel.editTarget?.id) { _, id in
                if id != nil { composerFocused = true }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    viewModel.flushDraft()
                    // Свернули приложение — открытые сообщения снова закрыты.
                    reveal.hideAll()
                }
                // Пуши реакций, пока приложение было в фоне, могли потеряться: сверить с сервером.
                if phase == .active { Task { await viewModel.refreshReactions() } }
            }
    }

    @ViewBuilder
    private func deletionActions(_ message: Message) -> some View {
        if viewModel.deletesWithoutChoice {
            Button("Удалить", role: .destructive) {
                Task { await viewModel.confirmDelete(message, forEveryone: viewModel.deletesEverywhere(message)) }
            }
        } else {
            if viewModel.canDeleteForEveryone(message) {
                Button(kind == .private ? "Удалить у меня и у собеседника" : "Удалить у всех", role: .destructive) {
                    Task { await viewModel.confirmDelete(message, forEveryone: true) }
                }
            }
            Button("Удалить у меня", role: .destructive) {
                Task { await viewModel.confirmDelete(message, forEveryone: false) }
            }
        }
        Button("Отмена", role: .cancel) { viewModel.deletionCandidate = nil }
    }

    private var headerStatus: ChatHeaderStatus {
        profile?.headerStatus(live()) ?? .none
    }

    @ViewBuilder
    private var headerAvatar: some View {
        if let profile {
            ChatHeaderAvatar(viewModel: profile, size: 44, reservesRingSpace: true)
        } else if viewModel.isSavedMessages {
            ChatAvatarView(avatar: ChatAvatar(kind: .savedMessages, colorIndex: 0), size: 36)
                .frame(width: 44, height: 44)
        } else {
            StoryRingAvatar(
                avatar: ChatAvatar(kind: .initials(ChatAvatar.initials(for: headerTitle)),
                                   colorIndex: ChatAvatar.colorIndex(for: viewModel.peerId ?? viewModel.chatId)),
                ring: nil, size: 44, reservesRingSpace: true
            )
        }
    }

    /// Владелец колец в шапке. В приватном режиме колец нет.
    private var storyOwner: String? {
        guard !privateMode.isMasked, let card = profile?.shown else { return nil }
        switch card.kind {
        case .user, .bot: return card.peerId
        case .group, .channel: return viewModel.chatId
        case .saved: return nil
        }
    }

    private var storyKind: StoryOwner.Kind {
        switch profile?.shown.kind {
        case .group: .chat
        case .channel: .channel
        default: .user
        }
    }

    private func openProfile() {
        guard profile != nil else { return }
        composerFocused = false
        profileShown = true
    }

    /// Бот с мини-приложением: над полем ввода «Открыть приложение».
    private var openAppAction: (() -> Void)? {
        guard makeBotApp != nil, let card = profile?.profile, card.kind == .bot, card.hasWebApp,
              let botId = card.peerId else { return nil }
        let appTitle = card.title.isEmpty ? title : card.title
        return { [viewModel] in viewModel.openBotApp(botId: botId, title: appTitle) }
    }

    /// Канал или группа вне списка (открыты из поиска) с публичной ссылкой: вместо плашки
    /// «Подписаться» или «Вступить».
    private var joinAction: ChatComposer.Join? {
        guard canWrite == nil, let card = profile?.profile, let link = card.linkURL?.absoluteString else { return nil }
        let label: String
        switch card.kind {
        case .channel: label = "Подписаться"
        case .group: label = "Вступить"
        case .user, .bot, .saved: return nil
        }
        return ChatComposer.Join(label: label, busy: viewModel.joining) { [viewModel] in
            Task { await viewModel.join(link: link) }
        }
    }

    /// Родные комментарии канала: флаг из списка чатов, а если список не знает (канал из поиска
    /// или карточка в списке без опций) — из карточки канала.
    private var comments: Bool? {
        commentsEnabled ?? profile?.profile?.commentsEnabled
    }

    /// Название в шапке: из списка чатов, а у чата вне списка (канал из поиска) — из карточки,
    /// когда она пришла. Без неё было бы общее «Чат».
    private var headerTitle: String {
        if canWrite == nil, let name = profile?.profile?.title, !name.isEmpty { return name }
        return title
    }

    /// Тип чата для ленты и поля ввода: из списка, а для чата вне списка — из карточки.
    private var kind: ChatType {
        guard canWrite == nil, let card = profile?.profile else { return chatType }
        switch card.kind {
        case .channel: return .channel
        case .group: return .group
        case .user, .bot, .saved: return .private
        }
    }

    /// Поле ввода только там, где можно писать. Чат вне списка (канал из поиска, группа по
    /// ссылке до вступления) — только личный диалог, бот или «Избранное», и только когда
    /// карточка уже пришла: иначе поле мелькнуло бы и пропало.
    private var writable: Bool {
        if let canWrite { return canWrite }
        switch profile?.profile?.kind {
        case .user?, .bot?, .saved?: return true
        case .group?, .channel?, nil: return false
        }
    }

    /// Профиль, открытый из чата: звук, общие медиа и действия, которые раньше были в меню шапки.
    private func profileContext(for card: ChatProfileViewModel) -> ChatProfileContext {
        // Чат вне списка (канал из поиска) не удалить и не заглушить: его нет среди чатов аккаунта.
        let listed = canWrite != nil
        var context = ChatProfileContext(
            chat: viewModel,
            isMuted: isMuted,
            onToggleMute: listed ? onToggleMute : nil,
            onShowMessage: { showInChat($0) },
            onEraseChat: listed ? onEraseChat : nil
        )
        if listed, card.shown.kind == .channel || card.shown.kind == .group {
            context.onLeave = onLeave
        }
        if let join = joinAction {
            context.join = (label: join.label, run: join.action)
        }
        if let onOpenChat {
            context.onOpenChat = { id in
                profileShown = false
                onOpenChat(id)
            }
        }
        context.onSearch = { closeProfile { searchShown = true } }
        if writable {
            context.onPoll = { closeProfile { pollShown = true } }
            context.onSchedule = { closeProfile { scheduleShown = true } }
        }
        if kind == .private, let peerId = viewModel.peerId, card.shown.kind == .user, let onCall {
            let peer = CallCenter.Peer(id: peerId, name: card.shown.title, avatarURL: card.shown.avatarURL)
            context.onCall = { video in
                profileShown = false
                onCall(peer, video)
            }
        }
        return context
    }

    /// Действие из профиля, которое живёт на экране чата: профиль уезжает, потом оно открывается.
    private func closeProfile(then action: @escaping () -> Void) {
        profileShown = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    /// «Показать в чате» из общих медиа: профиль закрывается, сообщение подсвечивается.
    private func showInChat(_ message: Message) {
        profileShown = false
        Task {
            // Сначала уезжает профиль, потом лента прокручивается к сообщению.
            try? await Task.sleep(for: .milliseconds(350))
            viewModel.focusReply(message.id)
        }
    }

    /// Заголовок для системы: в приватном режиме общий, иначе название чата.
    private var shownTitle: String {
        privateMode.isMasked ? maskedTitle : headerTitle
    }

    private var maskedTitle: String {
        PrivateModeMask.chatTitle(type: kind, isSavedMessages: viewModel.isSavedMessages)
    }

    /// Верх ленты в приватном режиме: стеклянная капсула «Отключить приватный режим»
    /// и подсказка, что сообщение открывается касанием.
    private func pinBanner(id: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orbitleAccent)
            Button {
                viewModel.focusReply(id)
            } label: {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button("Снять") { Task { await viewModel.unpin() } }
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Закреплено: \(text)")
    }

    private var privateModeBanner: some View {
        OrbitleGlassGroup(spacing: 6) {
            VStack(spacing: 6) {
                if let settings = privateModeSettings {
                    Button {
                        withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { settings.setEnabled(false) }
                    } label: {
                        Label("Отключить приватный режим", systemImage: "eye.slash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .orbitleGlassCapsule()
                }
                if !viewModel.messages.isEmpty {
                    Text(PrivateModeMask.revealHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .orbitleGlassRounded(radius: 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .transition(.orbitleBar(edge: .top, reduceMotion: reduceMotion))
    }

    private var deletionShown: Binding<Bool> {
        Binding(
            get: { viewModel.deletionCandidate != nil },
            set: { if !$0 { viewModel.deletionCandidate = nil } }
        )
    }

    private var forwardShown: Binding<Bool> {
        Binding(
            get: { viewModel.forwardCandidate != nil },
            set: { if !$0 { viewModel.forwardCandidate = nil } }
        )
    }

    /// В канале с комментариями счётчики постов спрашиваются у сервера, когда лента меняется.
    private var wantsCommentCounts: Bool {
        kind == .channel && comments == true
    }
}
