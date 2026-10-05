import SwiftUI
import UIKit
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
    /// Верх нижних кнопок (поле ввода или плашка канала) в глобальных координатах: от него
    /// поднимается мягкое размытие низа. `0` — ещё не измерено.
    var bottomControlsTop: CGFloat = 0
    /// Где на экране лежит фон с обоями: низ ленты тает в ту же картинку.
    var wallpaperFrame: CGRect = .zero
    /// Эмодзи двойного нажатия. `nil` — быстрая реакция выключена.
    var quickReaction: String? = nil
    /// Низ ленты виден (пока виден, новые сообщения прокручивают ленту сами), число новых
    /// на кнопке «вниз» и прыжок к последнему сообщению.
    @State private var bottom = TranscriptBottomState()
    @State private var isOpening = true
    @State private var position: String?
    @State private var olderAnchor: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatWallpaper) private var wallpaper

    static let bottomId = "transcript-bottom"
    /// Отступ ленты от краёв: пузыри ближе к краю экрана.
    static let feedInset: CGFloat = 8
    /// Сколько последних сообщений прогревают кэш картинок при открытии и новых сообщениях.
    static let prefetchCount = 40
    /// iOS 17 требует ручного следования за новыми сообщениями; iOS 18 удерживает
    /// низ через sizeChanges. Первое открытие на обеих версиях использует id сообщения.
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
                    // Серверное обогащение (реакции/счётчики) не запускает анимацию
                    // всей ленты. Действия пользователя анимируются у своего пузыря.
                }
                // Чат открывается сразу внизу, а не сверху до загрузки истории.
                .defaultScrollAnchor(.bottom)
                // Адресуем реальное сообщение: пустая метка за ещё не измеренными
                // высокими постами не является надёжной целью первого позиционирования.
                .scrollPosition(id: $position, anchor: .bottom)
                .coordinateSpace(name: "transcript-viewport")
                .modifier(TranscriptBottomTracking(bottom: $bottom, viewportHeight: geo.size.height))
                // Клавиатура уходит, когда ленту тянут вниз вслед за пальцем или просто касаются
                // её: касание не мешает кнопкам пузырей, жест срабатывает вместе с ними.
                .scrollDismissesKeyboard(.interactively)
                // Касание ленты прячет клавиатуру. Без клавиатуры жест выключен, чтобы лента
                // не ждала его при каждом касании.
                .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = false }, including: focus.wrappedValue ? .all : .subviews)
                .onChange(of: viewModel.transcriptVersion, initial: true) { _, _ in follow(proxy) }
                .onChange(of: viewModel.isRestoringHistory) { _, restoring in
                    guard !restoring else { return }
                    let opening = isOpening
                    isOpening = false
                    guard opening || bottom.atBottom else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if opening { openAtStart(proxy) } else { position = viewModel.messages.last?.id }
                    }
                }
                .chatSystemEdgeEffectHidden()
                // Лёгкий переход в фон под нижними кнопками. Раньше кнопки «вниз»: она рисуется поверх.
                .overlay { ChatBottomBlur(controlsTop: bottomControlsTop, wallpaper: wallpaper, wallpaperFrame: wallpaperFrame) }
                .overlay(alignment: .bottom) {
                    if viewModel.showsSavedPlaceholder {
                        SavedMessagesPlaceholder()
                            .padding(.horizontal, OrbitleTheme.pad + 8)
                            .padding(.bottom, 24)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if viewModel.messages.isEmpty && viewModel.isRestoringHistory {
                        ProgressView("Загрузка сообщений…")
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    } else if viewModel.messages.isEmpty, let error = viewModel.historyError {
                        VStack(spacing: 12) {
                            Text(error.userMessage ?? "Не удалось загрузить сообщения").multilineTextAlignment(.center)
                            Button("Повторить") { Task { await viewModel.loadLatest() } }
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                    bottom.beginReadingHistory()
                    proxy.scrollTo(id, anchor: .center)
                }
                .onChange(of: geo.size.height) { _, _ in
                    // iOS 17 не умеет sizeChanges: клавиатура и многострочный ввод
                    // должны удерживать последнее сообщение, только если читатель внизу.
                    guard Self.scrollsToBottomByHand, bottom.atBottom, !isOpening else { return }
                    jumpToBottom(proxy)
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
        } else if viewModel.latestLoaded && viewModel.messages.isEmpty && !viewModel.isRestoringHistory && viewModel.historyError == nil && !viewModel.showsSavedPlaceholder {
            Text("Здесь пока нет сообщений")
                .foregroundStyle(.secondary)
                .padding(24)
        } else if !viewModel.messages.isEmpty {
            Button("Раньше") {
                // Старое ложится сверху: верхнее сообщение остаётся на месте.
                olderAnchor = viewModel.messages.first?.id
                Task {
                    await viewModel.loadOlder()
                }
            }
            .disabled(viewModel.isLoadingOlder || viewModel.isRestoringHistory)
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
    /// Первое положение ленты: разделитель непрочитанных у верха экрана, иначе последнее сообщение.
    private func openAtStart(_ proxy: ScrollViewProxy) {
        if let anchor = viewModel.unreadAnchorId {
            bottom.beginReadingHistory()
            proxy.scrollTo(anchor, anchor: UnitPoint(x: 0.5, y: 0.12))
        } else {
            position = viewModel.messages.last?.id
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard !viewModel.messages.isEmpty else { return }
        let change = viewModel.messagesChange
        if case .prepended = change, let anchor = olderAnchor {
            olderAnchor = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(anchor, anchor: .top) }
            return
        }
        if isOpening {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { openAtStart(proxy) }
            if !viewModel.isRestoringHistory { isOpening = false }
            return
        }
        if viewModel.isRestoringHistory || change == .reload || change == .initial {
            // Первое открытие — сразу к последнему. Вернулись в чат (из профиля собеседника),
            // читая историю, — место в ленте не теряется.
            if bottom.atBottom {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { position = viewModel.messages.last?.id }
            }
            return
        }
        guard case .appended(let count) = change, count > 0 else { return }
        let added = viewModel.messages.suffix(count)
        // iOS 18 удерживает низ в той же layout-транзакции. Второй scrollTo с
        // анимацией конкурировал с sizeChanges и сдвигал пузыри повторно.
        if bottom.atBottom && !Self.scrollsToBottomByHand { return }
        if bottom.atBottom || added.contains(where: viewModel.isOutgoing) {
            scrollToLatest(proxy)
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
            maxWidth: min(520, max(0, width - Self.feedInset * 2) * OrbitleTheme.bubbleMax),
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
            canTranscribe: viewModel.canTranscribe(message),
            quickReaction: quickReaction
        )
    }

    /// Кнопка комментариев — только под постами канала с включёнными родными комментариями
    /// (опция `COMMENTS: true`, как в Komet). Без опции их нет: обсуждение такого канала, если
    /// оно есть, ведёт бот кнопкой под постом.
    private func allowsComments(_ message: Message) -> Bool {
        chatType == .channel && commentsEnabled == true
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
                            .foregroundStyle(Color.orbitleOnAccent)
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
                .foregroundStyle(Color.orbitleOnAccent)
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
/// же кадре, без второго рывка. Где низ, на обеих версиях говорит метка низа (на iOS 18
/// ещё и расстояние до низа, но только чтобы признак включить).
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
                // Доезд до низа по расстоянию — только признак «внизу»; уход от низа решает
                // метка низа и только под пальцем (см. `TranscriptBottomState.markerMoved`).
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.contentOffset.y - geometry.containerSize.height
                } action: { _, distance in
                    update { $0.scrolled(distance: Double(distance), dragging: false) }
                }
                .onPreferenceChange(TranscriptBottomPreference.self) { bottomY in
                    update { $0.markerMoved(bottomY: Double(bottomY), viewportHeight: Double(viewportHeight), dragging: dragging) }
                }
        } else {
            content
                .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                    dragging = true
                    update { $0.userTookOver() }
                }.onEnded { _ in
                    dragging = false
                })
                .onPreferenceChange(TranscriptBottomPreference.self) { bottomY in
                    update { $0.markerMoved(bottomY: Double(bottomY), viewportHeight: Double(viewportHeight), dragging: dragging) }
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
