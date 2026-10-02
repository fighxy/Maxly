import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Лента чата: пузыри, разделители дней, «Раньше», кнопка «вниз» и удержание низа.
///
/// Ячейка перерисовывается, только если поменялось её содержимое. Раньше
/// каждый пузырь сам читал общие свойства модели (ход голосового, загрузки, подсветку),
/// и любое их изменение — голосовое пишет ход 10 раз в секунду — перерисовывало все
/// видимые пузыри: лента подтормаживала. Теперь лента собирает для каждого пузыря его
/// значения (`TranscriptBubble.Snapshot`), а пузырь сравнивается целиком (`equatable`).
struct ChatTranscript: View {
    @Bindable var viewModel: ChatViewModel
    let chatType: ChatType
    let commentsEnabled: Bool?
    let canWrite: Bool
    let reveal: PrivateModeReveal
    var focus: FocusState<Bool>.Binding
    /// Низ ленты виден (пока виден, новые сообщения прокручивают ленту сами), число новых
    /// на кнопке «вниз» и прыжок к последнему сообщению.
    @State private var bottom = TranscriptBottomState()
    @State private var isOpening = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let bottomId = "transcript-bottom"
    /// Отступ ленты от краёв: пузыри ближе к краю экрана.
    static let feedInset: CGFloat = 8
    /// Сколько последних сообщений прогревают кэш картинок при открытии и новых сообщениях.
    static let prefetchCount = 40
    /// На iOS 18 открытие и сверку держит низом сама прокрутка (`defaultScrollAnchor` для
    /// `.sizeChanges`). Ручной `scrollTo` к низу ленивой ленты до того, как строки измерены,
    /// иногда оставлял пустой экран, пока ленту не тронешь. На iOS 17 — как раньше.
    private static var scrollsToBottomByHand: Bool {
        if #available(iOS 18.0, *) { false } else { true }
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        header(proxy)
                        ForEach(viewModel.rows) { row in
                            TranscriptBubble(
                                state: state(for: row, width: geo.size.width),
                                viewModel: viewModel,
                                reveal: reveal
                            )
                            .equatable()
                            .id(row.id)
                            .transition(.orbitleBubble(outgoing: row.isOutgoing, reduceMotion: reduceMotion))
                        }
                        bottomMarker
                    }
                    .transaction { transaction in
                        if isOpening || viewModel.isRestoringHistory {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Self.feedInset)
                    .padding(.bottom, 8)
                    // Новое снизу, удалённое, переставленное — плавно; первая страница и старая
                    // история сверху — сразу, иначе лента дёргается. Правило в `CollectionChange`.
                    .animation(
                        bottom.atBottom && !viewModel.isRestoringHistory ? OrbitleMotion.transcript(viewModel.messagesChange, reduceMotion: reduceMotion) : nil,
                        value: viewModel.transcriptVersion
                    )
                    // Реакция или правка меняет размер пузыря: соседи раздвигаются плавно.
                    .animation(
                        viewModel.messagesChange == .none && !viewModel.isRestoringHistory && bottom.atBottom ? OrbitleMotion.quick(reduceMotion: reduceMotion) : nil,
                        value: viewModel.contentVersion
                    )
                }
                // Чат открывается сразу внизу, а не сверху до загрузки истории.
                .defaultScrollAnchor(.bottom)
                .coordinateSpace(name: "transcript-viewport")
                .modifier(TranscriptBottomTracking(bottom: $bottom, viewportHeight: geo.size.height))
                // Клавиатура уходит, когда ленту тянут вниз вслед за пальцем или просто касаются
                // её: касание не мешает кнопкам пузырей, жест срабатывает вместе с ними.
                .scrollDismissesKeyboard(.interactively)
                // Касание ленты прячет клавиатуру. Без клавиатуры жест выключен, чтобы лента
                // не ждала его при каждом касании.
                .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = false }, including: focus.wrappedValue ? .all : .subviews)
                .onChange(of: viewModel.transcriptVersion) { _, _ in follow(proxy) }
                .onChange(of: viewModel.isRestoringHistory) { _, restoring in
                    guard !restoring else { return }
                    let opening = isOpening
                    isOpening = false
                    guard Self.scrollsToBottomByHand, opening || bottom.atBottom else { return }
                    jumpToBottom(proxy)
                }
                .overlay(alignment: .bottom) {
                    if viewModel.showsSavedPlaceholder {
                        SavedMessagesPlaceholder()
                            .padding(.horizontal, OrbitleTheme.pad + 8)
                            .padding(.bottom, 24)
                            .transition(.opacity)
                    }
                }
                .animation(OrbitleMotion.fade, value: viewModel.showsSavedPlaceholder)
                .overlay(alignment: .bottomTrailing) {
                    Group {
                        if bottom.showsButton(hasMessages: !viewModel.messages.isEmpty) {
                            ScrollDownButton(unseen: bottom.unseen) { scrollToLatest(proxy) }
                                .padding(.trailing, OrbitleTheme.pad)
                                .padding(.bottom, 10)
                                .transition(.orbitlePop(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: bottom.atBottom)
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: bottom.unseen)
                }
                .onChange(of: viewModel.scrollToken) { _, _ in
                    guard let id = viewModel.scrollTarget else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
                // Картинки последних сообщений качаются заранее: пока лента
                // докручивается, фото уже на диске и проявляются сразу.
                .task(id: viewModel.transcriptVersion) {
                    let urls = Self.prefetchURLs(viewModel.messages.suffix(Self.prefetchCount))
                    guard !urls.isEmpty else { return }
                    await ImagePipeline.shared.prefetch(urls)
                }
            }
        }
    }

    // MARK: Шапка и низ

    @ViewBuilder
    private func header(_ proxy: ScrollViewProxy) -> some View {
        if let hint = viewModel.emptyHint {
            VStack(spacing: 12) {
                OrbitleMark(size: 56)
                    .foregroundStyle(.tertiary)
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
        } else if !viewModel.showsSavedPlaceholder {
            Button("Раньше") {
                // Старое ложится сверху: верхнее сообщение остаётся на месте.
                let first = viewModel.messages.first?.id
                Task {
                    await viewModel.loadOlder()
                    guard let first else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(first, anchor: .top) }
                }
            }
            .font(.footnote)
            .padding(.top, 8)
        }
    }

    /// Метка низа ленты: видна — значит, пользователь внизу (iOS 17).
    private var bottomMarker: some View {
        Color.clear
            .frame(height: 1)
            .id(Self.bottomId)
            .background {
                GeometryReader { marker in
                    Color.clear.preference(
                        key: TranscriptBottomPreference.self,
                        value: marker.frame(in: .named("transcript-viewport")).maxY
                    )
                }
            }
    }

    // MARK: Прокрутка

    /// Лента поменяла состав: новое внизу — к нему (своё всегда, чужое — если читатель внизу),
    /// иначе счётчик на кнопке «вниз». История, удаление и перестановка ленту не двигают.
    private func follow(_ proxy: ScrollViewProxy) {
        guard !viewModel.messages.isEmpty else { return }
        let change = viewModel.messagesChange
        if viewModel.isRestoringHistory || change == .reload || change == .initial {
            // Первое открытие — сразу к последнему. Вернулись в чат (из профиля собеседника),
            // читая историю, — место в ленте не теряется.
            if Self.scrollsToBottomByHand, isOpening || bottom.atBottom { jumpToBottom(proxy) }
            return
        }
        guard case .appended(let count) = change, count > 0 else { return }
        let added = viewModel.messages.suffix(count)
        if bottom.atBottom || added.contains(where: viewModel.isOutgoing) {
            withAnimation(OrbitleMotion.standard(reduceMotion: reduceMotion)) {
                proxy.scrollTo(Self.bottomId, anchor: .bottom)
            }
        } else {
            bottom.received(added.filter { !viewModel.isOutgoing($0) }.count)
        }
    }

    /// Кнопка «вниз»: плавно к последнему сообщению, затем без анимации до настоящего низа.
    /// Лента ленивая, и анимированный путь считается по прикидке высот ещё не измеренных
    /// строк: без доводки прокрутка иногда вставала выше последнего сообщения. Доводка
    /// повторяется на следующем проходе цикла — к нему строки у низа уже измерены.
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        let jump = bottom.beginJump()
        withAnimation(OrbitleMotion.standard(reduceMotion: reduceMotion)) {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        } completion: {
            guard bottom.finishJump(jump) else { return }
            jumpToBottom(proxy)
            Task { @MainActor in
                await Task.yield()
                guard bottom.atBottom, bottom.jump == nil else { return }
                jumpToBottom(proxy)
            }
        }
    }

    private func jumpToBottom(_ proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
    }

    // MARK: Значения пузыря

    private func state(for row: TranscriptRow, width: CGFloat) -> TranscriptBubble.Snapshot {
        let message = row.message
        let showsAuthors = chatType == .group
        let reacts = viewModel.canReact(message)
        let loading = viewModel.loadingMediaId.flatMap { id in
            message.content.attachments.contains { $0.id == id } ? id : nil
        }
        let round = viewModel.roundPlayback.flatMap { playback in
            message.content.visuals.contains { $0.id == playback.id } ? playback : nil
        }
        return TranscriptBubble.Snapshot(
            row: row,
            maxWidth: width * OrbitleTheme.bubbleMax,
            showsAuthorName: showsAuthors && row.showsAuthorName,
            showsAuthorAvatar: showsAuthors && row.showsAuthorAvatar,
            reservesAvatar: showsAuthors,
            allowsComments: allowsComments(message),
            canWrite: canWrite,
            showsReactionUsers: chatType == .group,
            isRevealed: reveal.isRevealed(message.id),
            highlighted: viewModel.highlightedId == message.id,
            phase: message.content.voices.first.map { viewModel.voicePhase(for: $0.id) } ?? .idle,
            loadingId: loading,
            commentCount: viewModel.commentCount(for: message),
            uploadProgress: viewModel.uploadFraction(of: message),
            reacts: reacts,
            quickReactions: reacts ? viewModel.quickReactions(for: message) : [],
            canEdit: viewModel.canEdit(message),
            savesToPhotos: viewModel.canSave(message, to: .photos),
            savesToFiles: viewModel.canSave(message, to: .files),
            roundPlayback: round,
            transcript: message.content.voices.first.map { viewModel.transcriptPhase(for: $0) } ?? .collapsed,
            canTranscribe: viewModel.canTranscribe(message)
        )
    }

    /// Кнопка комментариев — только под постами канала с включёнными комментариями.
    private func allowsComments(_ message: Message) -> Bool {
        guard chatType == .channel else { return false }
        switch commentsEnabled {
        case true?: return true
        case false?: return false
        case nil: return message.content.comments != nil || viewModel.commentCounts[message.serverId ?? message.id] != nil
        }
    }

    /// Адреса фото, обложек видео и аватаров авторов: только сетевые, без повторов.
    static func prefetchURLs(_ messages: ArraySlice<Message>) -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        for message in messages.reversed() {
            var candidates = message.content.visuals.compactMap { $0.photo?.displayURL ?? $0.video?.displayURL }
            if let avatar = message.authorAvatarURL { candidates.append(avatar) }
            for url in candidates where !url.isFileURL && seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }
}

/// Пузырь ленты: все изменчивые значения приходят готовыми в `Snapshot`, поэтому пузырь
/// сравнивается целиком и не перерисовывается, если его значения не поменялись. Модель и
/// приватный режим нужны только для действий: тело пузыря их свойства не читает.
struct TranscriptBubble: View, Equatable {
    struct Snapshot: Equatable {
        var row: TranscriptRow
        var maxWidth: CGFloat
        var showsAuthorName: Bool
        var showsAuthorAvatar: Bool
        var reservesAvatar: Bool
        var allowsComments: Bool
        var canWrite: Bool
        /// «Кто отреагировал» — в группах. В личном чате и так видно, в канале — только числа.
        var showsReactionUsers: Bool
        /// Открыт касанием в приватном режиме.
        var isRevealed: Bool
        var highlighted: Bool
        var phase: VoicePhase
        /// Вложение этого сообщения, которое сейчас грузится; чужие сюда не попадают.
        var loadingId: String?
        var commentCount: Int?
        var uploadProgress: Double?
        var reacts: Bool
        var quickReactions: [String]
        var canEdit: Bool
        var savesToPhotos: Bool
        var savesToFiles: Bool
        /// Кружок этого сообщения, играющий в ленте.
        var roundPlayback: RoundPlayback?
        /// Расшифровка голосового: «→T», загрузка или раскрытый текст.
        var transcript: TranscriptPhase
        var canTranscribe: Bool
    }

    let state: Snapshot
    let viewModel: ChatViewModel
    let reveal: PrivateModeReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: TranscriptBubble, rhs: TranscriptBubble) -> Bool {
        lhs.state == rhs.state
    }

    private var message: Message { state.row.message }

    var body: some View {
        VStack(spacing: 2) {
            if let day = state.row.dayTitle {
                DaySeparator(day)
                    .transition(.opacity)
            }
            PrivateBubbleGate(
                isRevealed: state.isRevealed,
                accessibilityText: PrivateModeMask.messageText(for: message, outgoing: state.row.isOutgoing),
                onReveal: { [reveal, id = message.id] in
                    withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(id) }
                }
            ) {
                bubble
            } masked: {
                // Заглушка: «Вы получили сообщение», время и галочки; без имени, медиа и реакций.
                MessageBubble(
                    message: PrivateModeMask.message(message, outgoing: state.row.isOutgoing),
                    isOutgoing: state.row.isOutgoing,
                    maxWidth: state.maxWidth,
                    highlighted: state.highlighted,
                    showsAuthorAvatar: state.showsAuthorAvatar,
                    reservesAvatar: state.reservesAvatar,
                    group: state.row.group
                )
            }
        }
    }

    private var bubble: some View {
        let viewModel = viewModel
        let message = message
        return MessageBubble(
            message: message,
            isOutgoing: state.row.isOutgoing,
            maxWidth: state.maxWidth,
            phase: state.phase,
            allowsComments: state.allowsComments,
            highlighted: state.highlighted,
            showsAuthorName: state.showsAuthorName,
            showsAuthorAvatar: state.showsAuthorAvatar,
            reservesAvatar: state.reservesAvatar,
            group: state.row.group,
            loadingId: state.loadingId,
            commentCount: state.commentCount,
            onRetry: { Task { await viewModel.retry(id: message.id) } },
            onReply: { viewModel.beginReply(to: message) },
            onReact: { emoji in Task { await viewModel.toggleReaction(messageId: message.id, emoji: emoji) } },
            onComments: { viewModel.openComments(message) },
            onOpen: { viewModel.presentMedia(message, startId: $0) },
            onVoice: { viewModel.toggleVoice(message) },
            onFile: { viewModel.openFile(message, attachmentId: $0) },
            onFocusReply: { viewModel.focusReply($0) },
            onForward: { viewModel.requestForward(message) },
            onDelete: { viewModel.requestDelete(message) },
            onEdit: state.canEdit ? { viewModel.beginEdit(message) } : nil,
            allowsReply: state.canWrite,
            allowsReactions: state.reacts,
            quickReactions: state.reacts ? state.quickReactions : ReactionPalette.fallback,
            onMoreReactions: state.reacts ? { viewModel.showMoreReactions(message) } : nil,
            onReactionUsers: state.reacts && state.showsReactionUsers ? { viewModel.showReactionUsers(message) } : nil,
            uploadProgress: state.uploadProgress,
            onCancelUpload: { Task { await viewModel.cancelUpload(message) } },
            roundPlayer: roundPlayer,
            onSaveToPhotos: state.savesToPhotos ? { viewModel.save(message, to: .photos) } : nil,
            onSaveToFiles: state.savesToFiles ? { viewModel.save(message, to: .files) } : nil,
            transcript: state.transcript,
            // В одной анимации с лентой: пузырь растёт и сжимается, а соседние строки
            // сдвигаются плавно, а не скачком после него.
            onTranscribe: state.canTranscribe ? {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { viewModel.toggleTranscript(message) }
            } : nil
        )
    }

    /// Плеер, если в этом сообщении играет кружок.
    private var roundPlayer: AnyView? {
        guard let playback = state.roundPlayback else { return nil }
        let viewModel = viewModel
        let id = playback.id
        return AnyView(
            RoundVideoPlayer(url: playback.url) { viewModel.stopRound(id: id) }
                .id(playback)
        )
    }
}

/// Круглая кнопка «вниз» на стекле; число непрочитанных, пришедших сверху, — бейджем.
private struct ScrollDownButton: View {
    let unseen: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .orbitleGlassCircle(size: 42)
                .overlay(alignment: .top) {
                    if unseen > 0 {
                        Text(unseen > 99 ? "99+" : "\(unseen)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.orbitleAccent, in: Capsule())
                            .offset(y: -10)
                            .contentTransition(.numericText())
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unseen > 0 ? "Вниз, новых сообщений: \(unseen)" : "Вниз")
    }
}

/// Плашка пустого «Избранного», как в Max: знак закладки и что сюда сохранять.
private struct SavedMessagesPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.orbitleAccent, in: Circle())
            Text("Это избранное")
                .font(.headline)
            Text("Сохраняйте сообщения, медиа и файлы — доступ будет только у вас")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: 360)
        .orbitleGlassRounded(radius: 24)
        .accessibilityElement(children: .combine)
    }
}

/// «Лента внизу»: новые сообщения прокручивают её, кнопка «вниз» спрятана.
///
/// На iOS 18 признак меняет только прокрутка пальцем (и доезд до низа): новое сообщение,
/// подгруженная картинка или реакция удлиняют ленту, и раньше метка низа уезжала за экран —
/// признак сбрасывался, кнопка «вниз» мигала, а следующее сообщение уже не прокручивало
/// ленту. Пока лента внизу, при росте содержимого она держится низом
/// (`defaultScrollAnchor(.bottom, for: .sizeChanges)`): прежние пузыри уезжают вверх в том
/// же кадре, без второго рывка. На iOS 17 — метка низа, как раньше.
private struct TranscriptBottomTracking: ViewModifier {
    @Binding var bottom: TranscriptBottomState
    let viewportHeight: CGFloat
    @State private var dragging = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(bottom.atBottom ? .bottom : .top, for: .sizeChanges)
                .onScrollPhaseChange { _, phase in
                    dragging = phase == .tracking || phase == .interacting || phase == .decelerating
                    // Палец взял ленту во время прыжка «вниз»: доводки к низу не будет.
                    if phase == .tracking || phase == .interacting { update { $0.userTookOver() } }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.contentOffset.y - geometry.containerSize.height
                } action: { _, distance in
                    update { $0.scrolled(distance: Double(distance), dragging: dragging) }
                }
        } else {
            content
                .onPreferenceChange(TranscriptBottomPreference.self) { bottomY in
                    update { $0.markerMoved(bottomY: Double(bottomY), viewportHeight: Double(viewportHeight)) }
                }
        }
    }

    /// Прокрутка сообщает о себе каждый кадр: состояние пишется, только если поменялось,
    /// иначе лента пересобиралась бы на каждом кадре.
    private func update(_ change: (inout TranscriptBottomState) -> Void) {
        var next = bottom
        change(&next)
        if next != bottom { bottom = next }
    }
}

private struct TranscriptBottomPreference: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
