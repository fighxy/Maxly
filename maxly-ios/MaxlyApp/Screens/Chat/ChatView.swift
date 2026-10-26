import SwiftUI
import UIKit
import MaxlyData
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    /// Данные чата, службы и действия снаружи (`ChatScreenFactory`).
    let context: ChatScreenContext

    // Короткие имена входов: тело экрана читает их как раньше.
    private var title: String { context.info.title }
    private var commentsEnabled: Bool? { context.info.commentsEnabled }
    private var chatType: ChatType { context.info.chatType }
    private var canWrite: Bool? { context.info.canWrite }
    private var isMuted: Bool { context.info.isMuted }
    private var quickReaction: String? { context.info.quickReaction }
    private var opensProfile: Bool { context.info.opensProfile }
    private var forwardTargets: () -> [ChatListItem] { context.services.forwardTargets }
    private var mutedNow: (() -> Bool)? { context.services.mutedNow }
    private var contactList: (() -> AsyncStream<[Contact]>)? { context.services.contactList }
    private var stickerPanel: StickerPanelModel? { context.services.stickerPanel }
    private var live: () -> ChatHeaderLive { context.services.live }
    private var makeProfile: (() -> ChatProfileViewModel?)? { context.services.makeProfile }
    private var makeParticipantProfile: ((DialogDraft) -> ChatProfileViewModel?)? { context.services.makeParticipantProfile }
    private var chatAdmin: (any ChatAdminRepository)? { context.services.chatAdmin }
    private var makeBotApp: ((BotAppRequest) -> MiniAppModel)? { context.services.makeBotApp }
    private var listActions: ChatProfileListActions? { context.services.listActions }
    private var nowPlaying: VoiceNowPlaying? { context.services.nowPlaying }
    private var onToggleMute: (() -> Void)? { context.actions.toggleMute }
    private var onEraseChat: ((Bool, Bool) -> Void)? { context.actions.eraseChat }
    private var onLeave: (() -> Void)? { context.actions.leave }
    private var onOpenChat: ((String) -> Void)? { context.actions.openChat }
    private var onOpenDialog: ((DialogDraft) -> Void)? { context.actions.openDialog }
    private var onMarkUnread: ((Date) -> Void)? { context.actions.markUnread }
    private var onCall: ((CallCenter.Peer, Bool) -> Void)? { context.actions.call }
    private var onProfileOpened: () -> Void { context.actions.profileOpened }
    private var onOpenVoice: ((VoiceNowPlaying.Track) -> Void)? { context.actions.openVoice }
    @State private var participant: DialogDraft?
    /// Только что поставленная реакция: анимация значка и эффект вокруг (`ReactionBurstHost`).
    @State private var reactionBurst = ReactionBurstHost()
    /// Крестик у закрепа: открепить после подтверждения.
    @State private var unpinAsked = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var profile: ChatProfileViewModel?
    @State private var profileShown = false
    /// Плашку незнакомца закрыли крестиком в этом чате (`StrangerBarDismissals`).
    @State private var strangerBarDismissed = false
    /// Открыто подтверждение «Заблокировать» из плашки незнакомца.
    @State private var strangerBlockAsked = false
    @State private var forwardList: [ChatListItem] = []
    @State private var attachmentsShown = false
    /// Гифки gifka.me качаются и уходят по очереди: строка над полем ввода с отменой или «Повторить».
    @State private var gifQueue = GifSendQueue()
    /// Поиск раздела «GIF» панели: запрос и выдача остаются, пока открыт чат.
    @State private var gifPanel = GifPanelModel()
    /// Снимки с кнопки камеры в поле ввода (`CameraCaptureFlow`).
    @State private var cameraFlowShown = false
    /// Меню долгого нажатия на сообщение (`MessageMenuHost`).
    @State private var messageMenu = MessageMenuPresenter()
    @State private var panelShown = false
    /// Высота последней клавиатуры без нижнего отступа: панель встаёт на её место.
    @State private var keyboardHeight: CGFloat = 300
    /// Экранная клавиатура на экране: поле ввода стоит над ней, а без неё опускается ниже.
    @State private var keyboardShown = false
    /// Верх клавиатуры в глобальных координатах, пока она открыта: выше него читается лента.
    @State private var keyboardTop: CGFloat?
    /// Низ шапки (панель навигации и плашки) в глобальных координатах.
    @State private var headerBottom: CGFloat?
    /// Экран чата показан (между появлением и уходом): отметки прочтения уходят, только пока
    /// он показан и приложение активно.
    @State private var onScreen = false
    @State private var searchShown = false
    @State private var pollShown = false
    @State private var scheduleShown = false
    /// Верх нижних кнопок на экране, для мягкого размытия низа ленты.
    @State private var bottomControlsTop: CGFloat = 0
    /// Обои из «Оформления» и где они лежат на экране (для перехода в них у низа ленты).
    @Environment(\.chatWallpaper) private var wallpaper
    @State private var wallpaperFrame: CGRect = .zero
    /// Свои фото обоев: обои этого чата, иначе общие.
    @Environment(ChatWallpaperLibrary.self) private var wallpapers: ChatWallpaperLibrary?
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

    /// Фон этого чата: своё фото чата, «Без обоев» чата, общее фото или встроенные обои.
    private var chatBackground: ChatBackground {
        let key = ChatWallpaperLibrary.chatKey(account: viewModel.currentUserId, chatId: viewModel.chatId)
        return wallpapers?.background(chatKey: key) ?? .preset
    }

    /// Своё фото за лентой; `nil` — встроенные обои.
    private var customWallpaper: CustomWallpaperBackdrop? { chatBackground.photo }

    /// Встроенные обои этого чата: «Без обоев» у чата убирает и их.
    private var shownWallpaper: ChatWallpaper { chatBackground == .plain ? .plain : wallpaper }

    /// Лента с обоями, верхними плашками, полем ввода и панелью стикеров.
    private var transcriptLayer: some View {
        ChatTranscript(
            viewModel: viewModel,
            rules: rules,
            reveal: reveal,
            focus: $composerFocused,
            bottomControlsTop: bottomControlsTop,
            wallpaperFrame: wallpaperFrame,
            customWallpaper: customWallpaper,
            quickReaction: quickReaction,
            headerBottom: headerBottom,
            keyboardTop: keyboardTop,
            onAuthor: openParticipant
        )
        .environment(\.chatWallpaper, shownWallpaper)
        .environment(\.chatHasPhotoWallpaper, customWallpaper != nil)
        // Только что поставленная реакция: значок играет в плашке и сообщает своё место в этом
        // пространстве, эффект вокруг — слоем поверх ленты.
        .coordinateSpace(.named(ReactionBurstHost.space))
        .overlay { ReactionEffectLayer(host: reactionBurst) }
        .environment(\.messageMenuPresenter, messageMenu)
        // Анимодзи в сообщениях.
        .environment(\.animojiCatalog, viewModel.reactions.animoji)
        .environment(\.reactionBurst, reactionBurst)
        .task(id: viewModel.reactions.burst?.id) {
            reactionBurst.onShown = { [viewModel] id in viewModel.reactions.burstShown(id) }
            reactionBurst.update(viewModel.reactions.burst)
            guard let id = viewModel.reactions.burst?.id else { return }
            try? await Task.sleep(for: ReactionBurstHost.limit)
            guard !Task.isCancelled else { return }
            reactionBurst.expire(id)
        }
        // Анимации и эффекты быстрых реакций качаются заранее: по нажатию играют сразу.
        .task(id: viewModel.reactions.animoji.count + viewModel.reactions.effects.count) {
            let quick = ReactionPalette.quick(catalog: viewModel.reactions.catalog, mine: nil)
            let urls = quick.flatMap { emoji in
                [AnimojiText.lookup(catalog: viewModel.reactions.animoji, emoji: emoji), AnimojiText.lookup(catalog: viewModel.reactions.effects, emoji: emoji)].compactMap { $0 }
            }
            for url in urls where LottieStore.shared.cached(url) == nil {
                _ = await LottieStore.shared.animation(for: url)
            }
        }
        // Обои за лентой: на весь экран, под шапкой, полем ввода и клавиатурой, не
        // прокручиваются с сообщениями.
        .background {
            ChatWallpaperBackground(wallpaper: shownWallpaper, custom: customWallpaper)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { wallpaperFrame = $0 }
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBanners }
        // Режим включают и выключают и с другого экрана: капсула всё равно выезжает плавно.
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: privateMode)
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
            if keyboardShown { keyboardTop = Self.keyboardTop(note) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            setKeyboardShown(true, note)
            keyboardTop = Self.keyboardTop(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            setKeyboardShown(false, note)
            keyboardTop = nil
        }
    }

    private var topBanners: some View {
        VStack(spacing: 6) {
            topDock
            if privateMode.isMasked {
                privateModeBanner
            } else if let bar = rules.strangerBar {
                strangerBanner(bar)
                    .transition(.maxlyBar(edge: .top, reduceMotion: reduceMotion))
            }
        }
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: rules.strangerBar)
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: nowPlaying?.track != nil)
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.pins.banner?.id)
        // Низ шапки с плашками: выше него лента закрыта, сообщение там не прочитано.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { headerBottom = $0 }
    }

    /// Карточка под шапкой: сверху плеер голосового, под ним закреп. Без
    /// закрепа плеер висит один чуть ниже шапки.
    @ViewBuilder
    private var topDock: some View {
        let playing = nowPlaying?.track != nil
        let pinned = viewModel.pins.banner
        if playing || pinned != nil {
            TopDock {
                if let nowPlaying, playing {
                    VoicePlayerRow(model: nowPlaying) { track in
                        if track.chatId == viewModel.chatId {
                            viewModel.focusReply(track.messageId, at: track.date)
                        } else {
                            onOpenVoice?(track)
                        }
                    }
                }
                if playing, pinned != nil { TopDockDivider() }
                if let pinned {
                    pinBanner(id: pinned.id, text: pinned.text, counter: pinned.counter)
                }
            }
            .padding(.horizontal, MaxlyTheme.pad)
            .padding(.top, 6)
            .transition(.maxlyBar(edge: .top, reduceMotion: reduceMotion))
        }
    }

    /// Верх клавиатуры в глобальных координатах. Рамка в уведомлении — в координатах экрана,
    /// окно приложения может быть уже экрана (iPad). Клавиатура ниже окна ничего не закрывает.
    private static func keyboardTop(_ note: Notification) -> CGFloat? {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, frame.height > 0 else { return nil }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              let screen = window.windowScene?.screen else {
            return frame.minY
        }
        let local = window.convert(frame, from: screen.coordinateSpace)
        return local.minY < window.bounds.maxY ? local.minY : nil
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            if viewModel.selection.isActive {
                MessageSelectionBar(selection: viewModel.selection, messages: viewModel.messages)
                    .transition(.opacity)
            } else {
                composerControls
            }
        }
        // Строка отправки GIF выезжает и уходит; панель сжимается под поиск вместе с клавиатурой.
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: gifQueue.current?.id)
        .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: gifPanel.isSearching)
        // Без клавиатуры и панели капсулы опускаются в нижний отступ экрана:
        // над полоской «домой» и так остаётся место.
        .padding(.bottom, lowersControls ? -Self.controlsLowering : 0)
        // Верх поля ввода — от него лента тает в фон к низу экрана (`ChatBottomBlur`).
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { bottomControlsTop = $0 }
    }

    /// Поле ввода и панель стикеров.
    @ViewBuilder
    private var composerControls: some View {
        if let gif = gifQueue.current {
            GifDownloadBar(
                title: gif.media.title,
                failure: gif.failure,
                waiting: gifQueue.waiting,
                onRetry: { gifQueue.retry() },
                onCancel: { gifQueue.dismissCurrent() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        ChatComposer(
            viewModel: viewModel,
            recording: recording,
            focus: $composerFocused,
            attachmentsShown: $attachmentsShown,
            panelShown: $panelShown,
            bottomBar: rules.bottomBar,
            showsReadOnlyBar: canWrite != nil || profile?.profile != nil,
            isMuted: muted,
            // Звук чата вне списка не переключить: его нет среди чатов аккаунта.
            onToggleMute: canWrite == nil ? nil : onToggleMute,
            onOpenApp: openAppAction,
            action: bottomAction,
            onSearch: rules.searchInBottomBar ? { searchShown = true } : nil
        )
        if panelShown, rules.bottomBar == .composer, let stickerPanel {
            StickerPanel(
                model: stickerPanel,
                height: stickerPanelHeight,
                onEmoji: { viewModel.insertEmoji($0.emoji, animated: $0.animated) },
                onBackspace: { viewModel.deleteBackward() },
                onSticker: { sticker in Task { await viewModel.sendSticker(sticker) } },
                gifPanel: gifPanel,
                onPickGifka: { media, client in sendGif(media, client: client) }
            )
            .transition(.move(edge: .bottom))
        }
    }

    private var muted: Bool { mutedNow?() ?? isMuted }

    /// Панель стоит на месте клавиатуры. Пока ищут GIF, клавиатура открыта под ней: панель
    /// сжимается до поля поиска и ряда выдачи, чтобы лента осталась видна.
    private var stickerPanelHeight: CGFloat {
        gifPanel.isSearching ? min(keyboardHeight, Self.gifSearchPanelHeight) : keyboardHeight
    }

    /// Поле поиска, разделы, ряд выдачи и переключатель панели.
    static let gifSearchPanelHeight: CGFloat = 260

    /// На сколько нижние капсулы заходят в нижний отступ экрана.
    static let controlsLowering: CGFloat = 14

    /// Опускать капсулы: клавиатуры и панели стикеров нет, а внизу экрана есть отступ
    /// под полоску «домой» (на iPhone с кнопкой «Домой» его нет).
    private var lowersControls: Bool {
        guard !keyboardShown, !panelShown else { return false }
        let inset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
        return inset >= Self.controlsLowering * 2
    }

    /// Капсулы поднимаются и опускаются вместе с клавиатурой, её же кривой.
    private func setKeyboardShown(_ shown: Bool, _ note: Notification) {
        guard keyboardShown != shown else { return }
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) { keyboardShown = shown }
    }

    /// Шапка, переход в профиль и загрузка карточки чата.
    private var navigationLayer: some View {
        transcriptLayer
            // Видимость tab bar управляется стабильным MainTabView.
            // Системный заголовок (и подпись кнопки «назад» следующего экрана) размыть нельзя:
            // в приватном режиме там всегда общее «Личный чат» / «Групповой чат».
            .navigationTitle(shownTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Явная кнопка ниже: системный back включает также свайп закрытия чата.
            .navigationBarBackButtonHidden(true)
            .toolbar { headerToolbar }
            // Стеклянная капсула названия над лентой, под статус-баром мягкое размытие.
            .chatHeaderBlur()
            .navigationDestination(isPresented: $profileShown) { profileDestination }
            .navigationDestination(item: $participant) { dialog in
                ProfileDestination(make: { makeParticipantProfile?(dialog) }) {
                    participant = nil
                    onOpenDialog?(dialog)
                }
            }
            // Статус собеседника в шапке: события `presence` ядра, пока чат открыт.
            .task(id: profile == nil) { await profile?.watchPresence() }
            .task(id: opensProfile && profile != nil) {
                guard opensProfile, profile != nil else { return }
                openProfile()
                onProfileOpened()
            }
            .task {
                // Шапка: статус и аватар из карточки чата, она же открывается профилем.
                if profile == nil { profile = makeProfile?() }
                // Возврат из профиля тоже запускает эту задачу: свежую карточку не перезапрашиваем.
                await profile?.loadIfStale()
                viewModel.notePeer(profile?.shown.peerId, isBot: profile?.shown.kind == .bot)
                strangerBarDismissed = StrangerBarDismissals.contains(chatId: viewModel.chatId, account: viewModel.currentUserId)
                // Не из контактов: плашке нужно знать, не в чёрном ли списке человек.
                if profile?.contactAction == .add { await profile?.loadExtras() }
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
        if viewModel.selection.isActive {
            selectionToolbar
        } else {
            chatToolbar
        }
    }

    /// Шапка режима выбора: «Выбрано: N» и «Отмена».
    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(viewModel.selection.title(in: viewModel.messages))
                .font(.app(.headline))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        ToolbarItem(placement: .topBarLeading) {
            Button("Отмена") {
                withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { viewModel.selection.cancel() }
            }
        }
    }

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Назад", systemImage: "chevron.backward") { dismiss() }
                .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .principal) {
            Button(action: openProfile) {
                // Раз в минуту: «был(а) N минут назад» в шапке не застывает на времени открытия.
                TimelineView(.everyMinute) { context in
                    ChatHeaderTitle(
                        title: headerTitle,
                        maskedTitle: maskedTitle,
                        status: privateMode.isMasked ? .none : headerStatus(at: context.date),
                        isVerified: live().isVerified || profile?.isOfficial == true,
                        isMuted: muted
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shownTitle), открыть профиль")
        }
        // Поиск, опрос, отложенная отправка и звонки — в профиле чата: справа в шапке
        // только аватар.
        // Слот существует с первого кадра: загрузка профиля не перестраивает toolbar.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Общая подложка панели под своим видом — капсула шире высоты, и круглый аватар
            // сидел в овале. Подложку рисует сам аватар: стеклянный круг его размера.
            ToolbarItem(placement: .topBarTrailing) { avatarButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { avatarButton }
        }
        #else
        ToolbarItem(placement: .topBarTrailing) { avatarButton }
        #endif
    }

    private var avatarButton: some View {
        Button(action: openAvatar) {
            headerAvatar
                .maxlyGlassCircle(size: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профиль")
        .transaction { $0.animation = nil }
    }

    /// Касание аватара в шапке: истории собеседника, если есть, иначе профиль.
    private func openAvatar() {
        if let owner = storyOwner, stories?.ring(of: owner, kind: storyKind) != nil {
            stories?.open(owner, kind: storyKind)
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
                        guard let chatAdmin else { throw MaxlyError.rejected("Управление чатом недоступно") }
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
                        .environment(\.chatHasPhotoWallpaper, false)
                }
            }
            .sheet(item: $viewModel.reactions.pickerTarget) { message in
                ReactionPicker(
                    catalog: viewModel.reactions.catalog,
                    mine: message.content.reactions.mine,
                    onPick: { emoji in Task { await viewModel.reactions.pick(emoji) } },
                    onClose: { viewModel.reactions.pickerTarget = nil }
                )
                .environment(\.privateMode, .visible)
            }
            .sheet(isPresented: $searchShown) { searchSheet }
            .sheet(isPresented: $pollShown) {
                PollComposerSheet { title, answers in
                    Task { await viewModel.polls.send(title: title, answers: answers) }
                }
            }
            .sheet(isPresented: $viewModel.pins.listShown) { pinList }
            .confirmationDialog("Закрепить сообщение", isPresented: pinPromptShown, titleVisibility: .visible) {
                pinPromptButtons
            }
            .confirmationDialog("Открепить сообщение?", isPresented: $unpinAsked, titleVisibility: .visible) {
                Button("Открепить", role: .destructive) { Task { await viewModel.pins.unpin() } }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(isPresented: $scheduleShown) { ScheduleMessageSheet(viewModel: viewModel) }
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
            .fullScreenCover(isPresented: $cameraFlowShown) {
                CameraCaptureFlow(
                    onSend: { drafts, caption in
                        cameraFlowShown = false
                        Task { await viewModel.sendAttachments(drafts, caption: caption) }
                    },
                    onClose: { cameraFlowShown = false }
                )
                .environment(\.privateMode, .visible)
            }
            .sheet(item: $viewModel.reactions.users) { model in
                // Открывается из открытого пузыря — значит, смотреть его хотят.
                ReactionUsersView(model: model) { viewModel.reactions.users = nil }
                    .environment(\.privateMode, .visible)
            }
            .sheet(item: $viewModel.messageInfo) { model in
                messageInfoSheet(model)
            }
    }

    /// «Сведения» о сообщении. Касание читателя открывает личный диалог с ним.
    private func messageInfoSheet(_ model: MessageInfoViewModel) -> some View {
        let openReader: ((MessageReader) -> Void)? = onOpenDialog.map { open in
            { reader in
                let name = MessageInfoViewModel.name(of: reader)
                guard let draft = DialogDraft.with(peerId: reader.userId, me: viewModel.currentUserId, title: name, avatarURL: reader.avatarURL) else { return }
                viewModel.messageInfo = nil
                open(draft)
            }
        }
        // Открывается из открытого пузыря — значит, смотреть его хотят.
        return MessageInfoView(model: model, onOpenReader: openReader) { viewModel.messageInfo = nil }
            .environment(\.privateMode, .visible)
    }

    private var searchSheet: some View {
        ChatSearchSheet(model: viewModel) { hit in
            searchShown = false
            viewModel.focusReply(hit.messageId, at: hit.date)
        }
    }

    /// Ставит выбранную гифку в очередь: файл GIF качается и уходит фото, дальше пузырь
    /// показывает обычную загрузку с кольцом и отменой. Если скачать или отправить не вышло,
    /// строка над полем ввода остаётся с ошибкой и «Повторить».
    private func sendGif(_ media: GifkaMedia, client: GifkaClient) {
        let viewModel = viewModel
        gifQueue.enqueue(media, client: client) { draft in
            await viewModel.sendAttachments([draft], caption: "")
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
            .mediaViewerCover(item: unlessProfileShown($viewModel.attachments.viewer)) { request in
                MediaViewer(
                    request: request,
                    download: { await viewModel.attachments.downloadVideo($0, progress: $1) },
                    notice: viewModel.notice,
                    isSaving: viewModel.attachments.isSaving,
                    onSave: { viewModel.attachments.saveViewerSlide($0, to: $1) },
                    onShowInChat: showAction(request)
                ) { viewModel.attachments.viewer = nil }
                    .fileExportSheet(viewModel.attachments, fromViewer: true)
                    .environment(\.privateMode, .visible)
            }
            .fileExportSheet(viewModel.attachments, fromViewer: false)
            .fullScreenCover(item: unlessProfileShown($viewModel.attachments.openedFile)) { file in
                FileQuickLook(url: file.url, title: file.name) { viewModel.attachments.openedFile = nil }
                    .environment(\.privateMode, .visible)
            }
            .overlay {
                if recording.isVideo {
                    VideoNoteOverlay(session: recording, controlsTop: bottomControlsTop)
                }
            }
            .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: recording.isVideo)
            // Меню сообщения поверх всего экрана чата: лента под ним размыта.
            .overlay { MessageMenuHost(presenter: messageMenu) }
            .modifier(ChatHistoryLifecycle(model: viewModel, requestsComments: wantsCommentCounts))
    }

    /// Пока открыт профиль, просмотр из ленты не показывается: его показывает профиль.
    private func unlessProfileShown<Item>(_ item: Binding<Item?>) -> Binding<Item?> {
        profileShown ? .constant(nil) : item
    }

    private var lifecycleLayer: some View {
        coversLayer
            .onAppear {
                onScreen = true
                viewModel.setScreenActive(scenePhase == .active)
                recording.onStart = { [viewModel] in viewModel.voices.stop() }
                recording.onRecordingChange = { [viewModel] mode in
                    let kind: TypingKind?
                    switch mode {
                    case .voice?: kind = .audio
                    case .video?: kind = .videoMessage
                    case nil: kind = nil
                    }
                    viewModel.typingRecording(kind)
                }
                recording.onRecorded = { [viewModel] draft in
                    Task { await viewModel.sendAttachments([draft], caption: "") }
                }
                // Короткое нажатие камеры — снимок. Без камеры (симулятор) — лист вложений.
                recording.onCameraTap = {
                    composerFocused = false
                    panelShown = false
                    if ChatCameraPicker.isAvailable { cameraFlowShown = true } else { attachmentsShown = true }
                }
            }
            .onDisappear {
                // Ушли из чата (назад, профиль, другой чат): ждущая отметка прочтения снята.
                onScreen = false
                viewModel.endReadSession()
                panelShown = false
                recording.cancel()
                messageMenu.dismiss()
                reveal.hideAll()
            }
            // Режим выключили или сменили вид — открытые пузыри снова закрыты при следующем включении.
            .onChange(of: privateMode) { _, _ in
                messageMenu.dismiss()
                reveal.hideAll()
            }
            .onChange(of: reveal.revealed) { _, ids in
                if privateMode.isMasked, let request = messageMenu.request, !ids.contains(request.id) {
                    messageMenu.dismiss()
                }
            }
            // «Я печатаю» уходит, только пока сюда можно писать; панель стикеров — «выбирает стикер».
            .onChange(of: writable, initial: true) { _, value in viewModel.typingAllowed = value }
            .onChange(of: panelShown) { _, shown in
                if shown { viewModel.typingStickerPanelOpened() }
            }
            .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.notice)
    }

    /// Режим выбора нескольких сообщений: подтверждение удаления, выбор чатов для пересылки
    /// и права для правил удаления.
    private var selectionLayer: some View {
        lifecycleLayer
            .sheet(item: selectionDeleteRequest) { request in
                MessageSelectionDeleteSheet(
                    request: request,
                    chatType: kind,
                    onDelete: { forEveryone in Task { await viewModel.selection.confirmDelete(request, forEveryone: forEveryone) } },
                    onCancel: { viewModel.selection.deleteRequest = nil }
                )
            }
            .sheet(isPresented: batchForwardShown) {
                ForwardPickerView(
                    targets: forwardList,
                    allowsMultiple: true,
                    onPick: { id in forwardBatch(to: [id], comment: nil) },
                    onPickMany: { ids, comment in forwardBatch(to: ids, comment: comment) },
                    onCancel: { viewModel.selection.forwardBatch = nil }
                )
            }
            .onChange(of: viewModel.selection.forwardBatch?.count) { _, count in
                if count != nil { forwardList = forwardTargets() }
            }
            // Права для правил удаления выбранного: в канале писать может только админ.
            .onChange(of: kind, initial: true) { _, _ in noteSelectionContext() }
            .onChange(of: writable) { _, _ in noteSelectionContext() }
            .onChange(of: headerTitle) { _, _ in noteSelectionContext() }
            // В режиме выбора клавиатура и панель стикеров уходят: внизу панель действий.
            .onChange(of: viewModel.selection.isActive) { _, active in
                guard active else { return }
                composerFocused = false
                panelShown = false
            }
    }

    /// Удаление и пересылка сообщения, ответ, правка, пометка «непрочитано» и фаза приложения.
    private var chatEvents: some View {
        selectionLayer
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
                // Фон или неактивное приложение (шторка, переключатель) снимают ждущую отметку:
                // невидимое не читается. Вернулись — читается то, что на экране.
                viewModel.setScreenActive(onScreen && phase == .active)
                if phase != .active {
                    messageMenu.dismiss()
                    recording.cancel()
                    viewModel.flushDraft()
                    // Свернули приложение — открытые сообщения снова закрыты.
                    reveal.hideAll()
                }
                // Пуши реакций, пока приложение было в фоне, могли потеряться: сверить с сервером.
                if phase == .active { Task { await viewModel.reactions.refresh() } }
            }
    }

    @ViewBuilder
    private func deletionActions(_ message: Message) -> some View {
        if viewModel.deletesWithoutChoice {
            Button("Удалить", role: .destructive) {
                Task { await viewModel.confirmDelete(message, forEveryone: viewModel.deletesEverywhere(message)) }
            }
        } else if viewModel.deletionForcesEveryone {
            Button("Удалить", role: .destructive) {
                Task { await viewModel.confirmDelete(message, forEveryone: true) }
            }
        } else {
            // Вариант по умолчанию от ядра (`forEveryoneByDefault`) — первым.
            if viewModel.deletionShowsEveryone, viewModel.deletionPrefersEveryone {
                deleteForEveryoneButton(message)
            }
            Button("Удалить у меня", role: .destructive) {
                Task { await viewModel.confirmDelete(message, forEveryone: false) }
            }
            if viewModel.deletionShowsEveryone, !viewModel.deletionPrefersEveryone {
                deleteForEveryoneButton(message)
            }
        }
        Button("Отмена", role: .cancel) { viewModel.deletionCandidate = nil }
    }

    private func deleteForEveryoneButton(_ message: Message) -> some View {
        Button(rules.deleteForAllTitle, role: .destructive) {
            Task { await viewModel.confirmDelete(message, forEveryone: true) }
        }
    }

    private func headerStatus(at date: Date) -> ChatHeaderStatus {
        profile?.headerStatus(live(), at: date) ?? .none
    }

    @ViewBuilder
    private var headerAvatar: some View {
        let size = Self.headerAvatarSize
        if let profile {
            // Место под кольцо — только когда есть истории: иначе аватар заполняет круг целиком.
            ChatHeaderAvatar(viewModel: profile, size: size, reservesRingSpace: hasStoryRing)
        } else if viewModel.isSavedMessages {
            ChatAvatarView(avatar: ChatAvatar(kind: .savedMessages, colorIndex: 0), size: size)
        } else {
            StoryRingAvatar(
                avatar: ChatAvatar(kind: .initials(ChatAvatar.initials(for: headerTitle)),
                                   colorIndex: ChatAvatar.colorIndex(for: viewModel.peerId ?? viewModel.chatId)),
                ring: nil, size: size
            )
        }
    }

    /// Аватар меньше стеклянного круга 44 pt: по краю виден стеклянный ободок, как у кнопки
    /// «назад». Аватар во весь круг закрывал стекло целиком.
    static let headerAvatarSize: CGFloat = 38

    /// У собеседника есть истории: аватар в шапке в кольце.
    private var hasStoryRing: Bool {
        guard let owner = storyOwner else { return false }
        return stories?.ring(of: owner, kind: storyKind) != nil
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

    private func openParticipant(_ message: Message) {
        guard rules.showsAuthors, makeParticipantProfile != nil,
              let dialog = DialogDraft.with(peerId: message.authorId, me: viewModel.currentUserId,
                  title: message.authorName, avatarURL: message.authorAvatarURL) else { return }
        composerFocused = false
        participant = dialog
    }

    private func openProfile() {
        guard profile != nil else { return }
        composerFocused = false
        profileShown = true
    }

    /// Бот с мини-приложением: слева от поля ввода «Открыть».
    private var openAppAction: (() -> Void)? {
        guard makeBotApp != nil, let card = profile?.profile, card.kind == .bot, card.hasWebApp,
              let botId = card.peerId else { return nil }
        let appTitle = card.title.isEmpty ? title : card.title
        return { [viewModel] in viewModel.openBotApp(botId: botId, title: appTitle) }
    }

    /// Кнопка вместо поля ввода: «Подписаться» / «Вступить» у канала или группы вне списка
    /// (по публичной ссылке), «Начать» в пустом диалоге с ботом.
    private var bottomAction: ChatComposer.Action? {
        switch rules.bottomBar {
        case .join:
            guard let link = profile?.profile?.linkURL?.absoluteString else { return nil }
            return ChatComposer.Action(busy: viewModel.joining) { [viewModel] in
                Task { await viewModel.join(link: link) }
            }
        case .startBot:
            guard let profile else { return nil }
            return ChatComposer.Action(busy: profile.isActing) { [viewModel] in
                Task {
                    guard await !profile.startBot() else { return }
                    viewModel.announce(profile.actionNotice ?? "Не удалось запустить бота")
                }
            }
        case .composer, .channelControls, .readOnly:
            return nil
        }
    }

    /// Что показывать в этом виде чата: поле ввода или плашка внизу, авторы, комментарии,
    /// «@», плашка незнакомца, варианты закрепа и удаления (`ChatScreenRules`).
    private var rules: ChatScreenRules {
        let card = profile?.profile
        var input = ChatScreenRules.Input(listedType: chatType, canWrite: canWrite, card: card?.kind)
        input.hasJoinLink = card?.linkURL != nil
        input.canToggleMute = canWrite != nil && onToggleMute != nil
        input.commentsEnabled = comments
        input.historyEmpty = viewModel.isHistoryEmpty
        input.contactAddable = profile?.contactAction == .add
        input.peerBlocked = profile?.isBlocked
        input.hasOwnMessages = viewModel.hasOwnMessages
        input.strangerBarDismissed = strangerBarDismissed
        return ChatScreenRules(input)
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
    private var kind: ChatType { rules.kind }

    /// Можно ли писать (`ChatScreenRules.writable`): «печатает» и правила выбора.
    private var writable: Bool { rules.writable }

    /// Профиль, открытый из чата: звук, общие медиа и действия, которые раньше были в меню шапки.
    private func profileContext(for card: ChatProfileViewModel) -> ChatProfileContext {
        // Чат вне списка (канал из поиска) не удалить и не заглушить: его нет среди чатов аккаунта.
        let listed = canWrite != nil
        var context = ChatProfileContext(
            chat: viewModel,
            isMuted: muted,
            mutedNow: mutedNow,
            onToggleMute: listed ? onToggleMute : nil,
            onShowMessage: { showInChat($0.id) },
            onEraseChat: listed ? onEraseChat : nil
        )
        context.onShowMessageId = { showInChat($0) }
        context.list = listed ? listActions : nil
        context.shareTargets = forwardTargets
        if rules.canLeave {
            context.onLeave = onLeave
        }
        if case .join(let label) = rules.bottomBar, let action = bottomAction {
            context.join = (label: label, run: action.run)
        }
        if let onOpenChat {
            context.onOpenChat = { id in
                profileShown = false
                onOpenChat(id)
            }
        }
        if let onOpenDialog {
            context.onOpenDialog = { draft in
                profileShown = false
                onOpenDialog(draft)
            }
        }
        context.onSearch = { closeProfile { searchShown = true } }
        if writable {
            context.onPoll = { closeProfile { pollShown = true } }
            context.onSchedule = { closeProfile { scheduleShown = true } }
        }
        if rules.canCall, let peerId = viewModel.peerId, let onCall {
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
    /// «Перейти к сообщению» из просмотра: лента едет к сообщению и подсвечивает его.
    private func showAction(_ request: MediaViewerRequest) -> (() -> Void)? {
        guard let id = request.messageId else { return nil }
        return { viewModel.focusReply(id) }
    }

    private func showInChat(_ messageId: String) {
        profileShown = false
        Task {
            // Сначала уезжает профиль, потом лента прокручивается к сообщению.
            try? await Task.sleep(for: .milliseconds(350))
            viewModel.focusReply(messageId)
        }
    }

    /// Заголовок для системы: в приватном режиме общий, иначе название чата.
    private var shownTitle: String {
        privateMode.isMasked ? maskedTitle : headerTitle
    }

    private var maskedTitle: String {
        PrivateModeMask.chatTitle(type: kind, isSavedMessages: viewModel.isSavedMessages)
    }

    private var pinPromptShown: Binding<Bool> {
        Binding(
            get: { viewModel.pins.prompt != nil },
            set: { if !$0 { viewModel.pins.prompt = nil } }
        )
    }

    @ViewBuilder
    private var pinPromptButtons: some View {
        switch rules.pinOptions {
        case .dialog:
            Button("Только у меня") { Task { await viewModel.pins.confirm(forMe: true, notify: true) } }
            Button("Закрепить") { Task { await viewModel.pins.confirm(forMe: false, notify: true) } }
        case .group:
            Button("Уведомить участников") { Task { await viewModel.pins.confirm(forMe: false, notify: true) } }
            Button("Закрепить без уведомления") { Task { await viewModel.pins.confirm(forMe: false, notify: false) } }
        case .channel:
            Button("Закрепить") { Task { await viewModel.pins.confirm(forMe: false, notify: true) } }
        }
        Button("Отмена", role: .cancel) {}
    }

    private var pinList: some View {
        NavigationStack {
            List {
                if viewModel.pins.list.pins.isEmpty {
                    Text("Закрепов нет")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.pins.list.pins, id: \.messageId) { pin in
                    Button {
                        viewModel.pins.listShown = false
                        viewModel.focusReply(pin.messageId)
                    } label: {
                        Text(pin.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .swipeActions {
                        Button("Снять", role: .destructive) {
                            Task { await viewModel.pins.unpin(messageId: pin.messageId) }
                        }
                    }
                }
            }
            .navigationTitle("Закреплённые")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { viewModel.pins.listShown = false }
                }
                if viewModel.pins.list.pins.count > 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Снять все") { Task { await viewModel.pins.unpinAll() } }
                    }
                }
            }
        }
    }

    private func pinBanner(id: String, text: String, counter: String?) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.pins.cycle()
            } label: {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(Color.maxlyAccent)
                        .frame(width: 2.5, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(counter.map { "Закреплённое сообщение · \($0)" } ?? "Закреплённое сообщение")
                            .font(.app(.subheadline, .semibold))
                            .foregroundStyle(Color.maxlyAccent)
                            .lineLimit(1)
                        Text(text)
                            .font(.app(.subheadline))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if viewModel.pins.list.pins.count > 1 {
                Button {
                    viewModel.pins.listShown = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Все закреплённые")
            }
            Button { unpinAsked = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Открепить")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Закреплено: \(text)")
    }

    /// Диалог с человеком не из контактов: «Добавить в контакты», пока сам ему не писал —
    /// ещё «Заблокировать», и крестик. Плашка уходит, когда человек в контактах, заблокирован
    /// или её закрыли.
    private func strangerBanner(_ bar: ChatScreenRules.StrangerBar) -> some View {
        HStack(spacing: 0) {
            Button {
                Task { await addStranger() }
            } label: {
                Text("Добавить в контакты")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color.maxlyAccent)
            if bar.offersBlock {
                Divider().frame(height: 20)
                Button {
                    strangerBlockAsked = true
                } label: {
                    Text("Заблокировать")
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.red)
            }
            Button {
                dismissStranger()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Скрыть")
        }
        .buttonStyle(.plain)
        .font(.app(.subheadline, .semibold))
        .disabled(profile?.isChangingContact == true || profile?.isActing == true)
        .padding(.leading, 6)
        .maxlyGlassCapsule(interactive: false)
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.top, 6)
        .confirmationDialog("Заблокировать \(headerTitle)?", isPresented: $strangerBlockAsked, titleVisibility: .visible) {
            Button("Заблокировать", role: .destructive) { Task { await blockStranger() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Этот человек не сможет писать вам и звонить.")
        }
    }

    private func addStranger() async {
        guard let profile else { return }
        if await profile.addToContacts() {
            viewModel.announce("Контакт добавлен")
        } else if let error = profile.contactError {
            viewModel.announce(error)
            profile.dismissContactError()
        }
    }

    private func blockStranger() async {
        guard let profile, profile.isBlocked != true else { return }
        await profile.toggleBlocked()
        if let notice = profile.actionNotice { viewModel.announce(notice) }
    }

    private func dismissStranger() {
        StrangerBarDismissals.insert(chatId: viewModel.chatId, account: viewModel.currentUserId)
        withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { strangerBarDismissed = true }
    }

    private var privateModeBanner: some View {
        MaxlyGlassGroup(spacing: 6) {
            VStack(spacing: 6) {
                if let settings = privateModeSettings {
                    Button {
                        withAnimation(MaxlyMotion.quick(reduceMotion: reduceMotion)) { settings.setEnabled(false) }
                    } label: {
                        Label("Отключить приватный режим", systemImage: "eye.slash")
                            .font(.app(.subheadline, .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .maxlyGlassCapsule()
                }
                if !viewModel.messages.isEmpty {
                    Text(PrivateModeMask.revealHint)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .maxlyGlassRounded(radius: 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .transition(.maxlyBar(edge: .top, reduceMotion: reduceMotion))
    }

    private var deletionShown: Binding<Bool> {
        Binding(
            get: { viewModel.deletionCandidate != nil },
            set: { if !$0 { viewModel.deletionCandidate = nil } }
        )
    }

    private var selectionDeleteRequest: Binding<MessageSelectionModel.DeleteRequest?> {
        Binding(
            get: { viewModel.selection.deleteRequest },
            set: { viewModel.selection.deleteRequest = $0 }
        )
    }

    private var batchForwardShown: Binding<Bool> {
        Binding(
            get: { viewModel.selection.forwardBatch != nil },
            set: { if !$0 { viewModel.selection.forwardBatch = nil } }
        )
    }

    private func forwardBatch(to targets: [String], comment: String?) {
        guard let batch = viewModel.selection.forwardBatch else { return }
        viewModel.selection.forwardBatch = nil
        Task { await viewModel.selection.forward(batch, to: targets, comment: comment) }
    }

    private func noteSelectionContext() {
        let selection = viewModel.selection
        selection.chatType = kind
        selection.isAdmin = rules.isChannelAdmin
        selection.peerName = kind == .private ? headerTitle : nil
    }

    private var forwardShown: Binding<Bool> {
        Binding(
            get: { viewModel.forwardCandidate != nil },
            set: { if !$0 { viewModel.forwardCandidate = nil } }
        )
    }

    /// В канале с комментариями счётчики постов спрашиваются у сервера, когда лента меняется.
    private var wantsCommentCounts: Bool {
        rules.allowsComments
    }
}

/// Закрытые крестиком плашки незнакомца: по чатам, своя для каждого аккаунта. Настройка
/// устройства: после переустановки плашка вернётся.
enum StrangerBarDismissals {
    private static func key(_ account: String) -> String { "maxly.chat.strangerBarDismissed.\(account)" }

    static func contains(chatId: String, account: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key(account)) ?? []).contains(chatId)
    }

    static func insert(chatId: String, account: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key(account)) ?? []
        guard !ids.contains(chatId) else { return }
        ids.append(chatId)
        UserDefaults.standard.set(ids, forKey: key(account))
    }
}
