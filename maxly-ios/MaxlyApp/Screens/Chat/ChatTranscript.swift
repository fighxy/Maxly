import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Лента чата: пузыри, разделители дней, подгрузка истории, кнопка «вниз» и удержание низа.
///
/// Положение в ленте: чат открывается на первом непрочитанном или там, где читатель
/// остался; старое подгружается само, когда показался верх ленты; переход к цитате, закрепу
/// или найденному сообщению ведёт к нему, даже если оно далеко в истории (модель приносит окно
/// вокруг него), а кнопка «вниз» сначала возвращает к сообщению, с которого перешли.
///
/// Ячейка перерисовывается, только если поменялось её содержимое. Раньше
/// каждый пузырь сам читал общие свойства модели (ход голосового, загрузки, подсветку),
/// и любое их изменение — голосовое пишет ход 10 раз в секунду — перерисовывало все
/// видимые пузыри: лента подтормаживала. Теперь лента собирает для каждого пузыря его
/// значения (`TranscriptBubble.Snapshot`), а пузырь сравнивается целиком (`equatable`).
///
/// Лента — `UICollectionView` (`TranscriptCollectionFeed`, `FeedCollectionController`).
/// Устройство и правила: `docs/chat-smoothness.md`.
struct ChatTranscript: View {
    @Bindable var viewModel: ChatViewModel
    /// Что показывать в этом виде чата (`ChatScreenRules`).
    let rules: ChatScreenRules
    let reveal: PrivateModeReveal
    var focus: FocusState<Bool>.Binding
    /// Верх нижних кнопок (поле ввода или плашка канала) в глобальных координатах: от него
    /// поднимается мягкое размытие низа. `0` — ещё не измерено.
    var bottomControlsTop: CGFloat = 0
    /// Где на экране лежит фон с обоями: низ ленты тает в ту же картинку.
    var wallpaperFrame: CGRect = .zero
    /// Своё фото за лентой (обои чата или общие); `nil` — встроенные обои.
    var customWallpaper: CustomWallpaperBackdrop? = nil
    /// Эмодзи двойного нажатия. `nil` — быстрая реакция выключена.
    var quickReaction: String? = nil
    /// Низ шапки (панель навигации и плашки под ней) в глобальных координатах: выше него
    /// сообщение не видно. `nil` — ещё не измерен.
    var headerBottom: CGFloat? = nil
    /// Верх открытой клавиатуры в глобальных координатах; `nil` — клавиатуры нет.
    var keyboardTop: CGFloat? = nil
    var onAuthor: (Message) -> Void = { _ in }
    /// Низ ленты виден (пока виден, новые сообщения прокручивают ленту сами), число новых
    /// на кнопке «вниз» и прыжок к последнему сообщению.
    @State private var bottom = TranscriptBottomState()
    /// Видимость кнопки «вниз» — по геометрии самой прокрутки (`ScrollDownVisibility`).
    @State private var downButton = ScrollDownVisibility()
    @State private var isOpening = true
    @State private var scroll = TranscriptScrollController()
    @State private var userScrolling = false
    @State private var openingTargetChosen = false
    /// Верх ленты на экране: не пришедшая страница старого спрашивается снова, пока он виден.
    @State private var headerVisible = false
    /// Рамки видимых строк для отметки прочтения. Не состояние экрана: прокрутка не
    /// перерисовывает ленту, модель узнаёт только смену самого нового увиденного.
    @State private var reads = TranscriptReadTracker()
    @State private var diagnostics = TranscriptDiagnostics()
    /// Наименьший индекс видимой строки — для prefetch истории до края (слой C).
    @State private var nearTopPrefix: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatWallpaper) private var wallpaper
    // Окружение пузырей для ячеек ленты: через границу UIKit оно само не проходит.
    @Environment(\.privateMode) private var privateMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.animojiCatalog) private var animojiCatalog
    @Environment(\.reactionBurst) private var reactionBurst
    @Environment(\.messageMenuPresenter) private var messageMenuPresenter
    @Environment(\.chatHasPhotoWallpaper) private var chatHasPhotoWallpaper
    @Environment(\.imageURLSizing) private var imageURLSizing
    @Environment(\.gifAutoplay) private var gifAutoplay

    static let feedInset: CGFloat = 8
    static let prefetchCount = 40
    /// Декод картинок под пузырь (~ширина экрана × bubbleMax × 2× scale).
    static let prefetchMaxPixel = 900

    var body: some View {
        GeometryReader { geo in
            collectionFeed(width: geo.size.width, dayPillTop: 8)
            .chatSystemEdgeEffectHidden()
            .overlay { ChatBottomBlur(controlsTop: bottomControlsTop, wallpaper: wallpaper, custom: customWallpaper, wallpaperFrame: wallpaperFrame) }
            .overlay(alignment: .bottom) {
                Group {
                    if viewModel.showsSavedPlaceholder {
                        SavedMessagesPlaceholder()
                            .padding(.horizontal, MaxlyTheme.pad + 8)
                            .padding(.bottom, 24)
                            .transition(.opacity)
                    }
                }
            }
            .overlay {
                if viewModel.isJumping {
                    ProgressView()
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
            .animation(MaxlyMotion.fade, value: viewModel.showsSavedPlaceholder)
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 14) {
                    // «@» над «вниз»: непрочитанные упоминания себя в группе.
                    if !isOpening && rules.showsMentionsButton && !viewModel.unreadMentions.isEmpty {
                        ChatJumpButton(content: .mention, count: viewModel.unreadMentions.count) {
                            viewModel.jumpToNextMention()
                        }
                        .transition(.maxlyPop(reduceMotion: reduceMotion))
                    }
                    if !isOpening && !viewModel.messages.isEmpty && (downButton.shown || viewModel.isJumped) {
                        ChatJumpButton(content: .down, count: viewModel.unreadBelow) { goDown() }
                            .transition(.maxlyPop(reduceMotion: reduceMotion))
                    }
                }
                .padding(.trailing, ChatComposer.trailingInset(canWrite: rules.bottomBar == .composer))
                .padding(.bottom, 10)
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: downButton.shown)
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.unreadBelow)
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.unreadMentions.count)
            }
            .onChange(of: viewModel.scrollToken) { _, _ in perform(viewModel.scrollTarget) }
            .onChange(of: bottomSignal) { _, _ in
                noteBottomIfReached()
                reportReads()
            }
            .onChange(of: isOpening) { _, opening in
                if !opening { reportReads() }
            }
            .task(id: shouldPrefetchOlder) {
                if shouldPrefetchOlder { await loadOlderFromTop() }
            }
            .onChange(of: headerBottom) { _, _ in measuredGeometry(); reportReads() }
            .onChange(of: bottomControlsTop) { _, _ in
                measuredGeometry()
                if bottom.followsLatest, !userScrolling, !isOpening, scroll.request == nil { requestLatest() }
                reportReads()
            }
            .onChange(of: keyboardTop) { _, _ in
                measuredGeometry()
                if bottom.followsLatest, !userScrolling, !isOpening, scroll.request == nil { requestLatest() }
                reportReads()
                recordScroll("keyboard", immediate: true)
            }
            .onAppear {
                recordScroll("appear", immediate: true)
                if isOpening {
                    viewModel.consumeScroll()
                    openAtStart()
                } else { perform(viewModel.scrollTarget) }
                reportReads()
            }
            .task {
                for delay in [150, 350, 1000, 2000] {
                    do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                    recordScroll("opening-settled", immediate: true)
                }
            }
            .onDisappear {
                recordScroll("disappear", immediate: true)
                viewModel.savePlace(visiblePlace ?? reads.place?.id, atBottom: bottom.atBottom)
                scroll.cancel()
                openingTargetChosen = false
                isOpening = true
                reads.reported = nil
                nearTopPrefix = nil
            }
            .onChange(of: geo.size.height) { _, _ in
                guard bottom.followsLatest, !userScrolling, !isOpening else { return }
                requestLatest()
            }
            .task(id: viewModel.transcriptVersion) {
                let plan = TranscriptImagePrefetch.plan(
                    messages: viewModel.messages,
                    visibleRange: nil,
                    scrollingTowardOlder: false
                )
                guard !plan.urls.isEmpty else { return }
                await ImagePipeline.shared.prefetchDecoded(
                    plan.urls.map { ($0, TranscriptImagePrefetch.maxPixel) }
                )
            }
        }
    }

    /// Prefetch старой истории: шапка видна или среди видимых есть одна из первых 20 строк.
    private var shouldPrefetchOlder: Bool {
        HistoryPrefetch.shouldLoadOlder(
            canLoadOlder: viewModel.canLoadOlder,
            isLoadingOlder: viewModel.isLoadingOlder,
            isRestoringHistory: viewModel.isRestoringHistory,
            isOpening: isOpening,
            headerVisible: headerVisible,
            visiblePrefix: nearTopPrefix
        )
    }

    private var nearTopActive: Bool {
        nearTopPrefix.map { $0 < HistoryPrefetch.triggerRows } ?? false
    }

    @ViewBuilder
    private func collectionFeed(width: CGFloat, dayPillTop: CGFloat) -> some View {
        let style = layoutStyle(width: width)
        TranscriptCollectionFeed(
            viewModel: viewModel,
            rows: viewModel.rows,
            revealMode: reveal,
            feedInset: Self.feedInset,
            reduceMotion: reduceMotion,
            liveChanges: !viewModel.isRestoringHistory && !isOpening,
            scrollRequest: scroll.request,
            stickToBottom: stickToBottom,
            reveal: revealTarget,
            header: headerKind,
            isJumped: viewModel.isJumped,
            headerBottom: headerBottom,
            composerTop: composerCover,
            environment: feedEnvironment,
            snapshot: { state(for: $0, width: width) },
            layoutKey: { layoutKey(for: $0, style: style) },
            estimate: { row, rowWidth in
                CGFloat(BubbleHeightCache.estimate(
                    row: row,
                    maxWidth: Double(Self.bubbleMaxWidth(rowWidth: rowWidth)),
                    reservesAvatar: style.showsAuthors
                ))
            },
            onAuthor: onAuthor,
            onFrames: { frames, viewport in
                applyCollectionFrames(frames, viewport: viewport)
            },
            onBottomDistance: { distance, visible in
                var next = downButton
                if next.update(distance: distance, visibleHeight: visible) { downButton = next }
            },
            onUserScroll: { moving, takeover in
                userScrolling = moving
                if takeover {
                    scroll.cancel()
                    bottom.userTookOver()
                    openingTargetChosen = true
                    isOpening = false
                    recordScroll("scroll-cancel=user", immediate: true)
                }
                measuredGeometry()
            },
            onTopVisible: { visible in
                if headerVisible != visible { headerVisible = visible }
            },
            onNearTopPrefix: { prefix in
                if nearTopPrefix != prefix { nearTopPrefix = prefix }
            },
            onLoadOlder: { Task { await loadOlderFromTop() } },
            onLoadNewer: { Task { await viewModel.loadNewer() } },
            onScrollFinished: { token, confirmed in
                guard scroll.finish(token) else { return }
                isOpening = false
                if !confirmed { bottom.beginReadingHistory() }
                recordScroll(confirmed ? "scroll-confirmed" : "scroll-unconfirmed", immediate: true)
                measuredGeometry()
                noteBottomIfReached()
                reportReads()
            },
            onPrefetchURLs: { urls in
                Task {
                    await ImagePipeline.shared.prefetchDecoded(
                        urls.map { ($0, Self.prefetchMaxPixel) }
                    )
                }
            }
        )
        // Лента на весь экран, под стеклом шапки и поля ввода: сообщения уходят под них, а не
        // обрезаются по краю. Место для чтения задают зазоры ленты (`FeedScroll.chromeInsets`):
        // перекрытие шапки и поля ввода. Клавиатуру лента не перекрывает.
        .ignoresSafeArea(.container, edges: .vertical)
        .modifier(FloatingDayOverlay(model: viewModel, topVisible: headerVisible, topPadding: dayPillTop))
        .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = false }, including: focus.wrappedValue ? .all : .subviews)
        .onChange(of: viewModel.transcriptVersion, initial: true) { _, _ in
            recordScroll("transcript-change", immediate: true)
            followCollection()
        }
        .onChange(of: viewModel.isRestoringHistory) { _, restoring in
            recordScroll("restoring-\(restoring)", immediate: true)
            guard !restoring else { return }
            if isOpening { openAtStart() }
        }
        .onAppear {
            if isOpening { openAtStart() }
        }
    }

    /// Служебная строка над сообщениями ленты на UICollectionView.
    private var headerKind: TranscriptCollectionFeed.HeaderKind {
        if let hint = viewModel.emptyHint { return .hint(hint) }
        let empty = viewModel.latestLoaded && viewModel.messages.isEmpty && !viewModel.isRestoringHistory
            && viewModel.historyError == nil && !viewModel.showsSavedPlaceholder
        if empty { return rules.showsChannelReady ? .channelReady : .empty }
        if !viewModel.messages.isEmpty && viewModel.canLoadOlder { return .olderLoader(loading: viewModel.isLoadingOlder) }
        return .none
    }

    private var feedEnvironment: FeedEnvironment {
        FeedEnvironment(
            privateMode: privateMode,
            dynamicTypeSize: dynamicTypeSize,
            animojiCatalog: animojiCatalog,
            reactionBurst: reactionBurst,
            messageMenuPresenter: messageMenuPresenter,
            chatWallpaper: wallpaper,
            chatHasPhotoWallpaper: chatHasPhotoWallpaper,
            imageURLSizing: imageURLSizing,
            gifAutoplay: gifAutoplay
        )
    }

    /// Ширина колонки пузыря по ширине строки ленты (лента без полей по краям).
    static func bubbleMaxWidth(rowWidth: CGFloat) -> CGFloat {
        min(520, max(0, rowWidth) * MaxlyTheme.bubbleMax)
    }

    /// Общее для всех строк, от чего зависит высота: ширина, шрифт и размер текста, вид чата,
    /// приватный режим, режим выбора.
    private func layoutStyle(width: CGFloat) -> TranscriptLayoutStyle {
        let typography = Typography.shared
        return TranscriptLayoutStyle(
            maxWidth: Self.bubbleMaxWidth(rowWidth: width - Self.feedInset * 2),
            showsAuthors: rules.showsAuthors,
            allowsComments: rules.allowsComments,
            isSelecting: viewModel.selection.isActive,
            privateMode: privateMode,
            dynamicTypeSize: dynamicTypeSize,
            font: typography.font,
            fontWeight: typography.weight,
            textSize: typography.textSize,
            animojiCount: animojiCatalog.count
        )
    }

    private func layoutKey(for row: TranscriptRow, style: TranscriptLayoutStyle) -> FeedLayoutKey {
        let message = row.message
        let voice = message.content.voices.first
        let round = viewModel.attachments.roundPlayback.map { playback in message.content.visuals.contains { $0.id == playback.id } } ?? false
        return FeedLayoutKey(TranscriptRowLayoutKey(
            row: row,
            style: style,
            isRevealed: reveal.isRevealed(message.id),
            transcript: voice.map { viewModel.transcripts.phase(for: $0) } ?? .collapsed,
            roundPlaying: round
        ))
    }

    /// Global row frames and viewport use the same coordinate system. A missing
    /// last frame is useful too: the collection has not laid that row out yet.
    private func recordScroll(_ event: String, immediate: Bool = false) {
        let last = viewModel.rows.last.flatMap { reads.rows[$0.id] }
        let viewport = reads.viewport
        let visible = reads.rows.values.filter { frame in
            viewport.map { frame.intersects($0.frame) } ?? false
        }.count
        diagnostics.context = [
            "chat": DiagnosticEvent.id(viewModel.chatId), "rows": String(viewModel.rows.count),
            "measured": String(reads.rows.count), "visible": String(visible), "opening": String(isOpening),
            "restoring": String(viewModel.isRestoringHistory), "at_bottom": String(bottom.atBottom),
            "jumped": String(viewModel.isJumped), "position": visiblePlace.map(DiagnosticEvent.id) ?? "nil",
            "following_latest": String(bottom.followsLatest), "scroll_command": scroll.request.map { String($0.token) } ?? "nil",
            "last_frame": TranscriptDiagnostics.frame(last), "viewport_frame": TranscriptDiagnostics.frame(viewport?.frame),
            "composer_top": TranscriptDiagnostics.n(bottomControlsTop), "keyboard_top": keyboardTop.map(TranscriptDiagnostics.n) ?? "nil",
            "header_bottom": headerBottom.map(TranscriptDiagnostics.n) ?? "nil", "content_top": TranscriptDiagnostics.n(contentTop),
            "visible_area": TranscriptDiagnostics.frame(visibleArea), "last_end_visible": String(bottom.lastEndVisible),
            "unread_below": String(viewModel.unreadBelow), "down_button": String(downButton.shown)
        ]
        diagnostics.record(event, immediate: immediate)
    }

    // MARK: Отметка прочтения

    /// Самое новое сообщение, у которого в видимой области не меньше 30 % высоты
    /// (`ReadVisibility`, `ReadMarkRules`). Область — рамка ленты без её безопасных отступов,
    /// ниже шапки и выше поля ввода и клавиатуры. Пока лента открывается (встаёт на
    /// разделитель или на прежнее место), ничего не сообщается: промежуточное положение у низа
    /// прочитало бы весь чат. Модель узнаёт только смену результата.
    private func reportReads() {
        guard !isOpening, scroll.request == nil, let viewport = reads.viewport else { return }
        let area = ReadVisibility.area(
            viewport: ReadSpan(minY: Double(viewport.frame.minY), maxY: Double(viewport.frame.maxY)),
            safeTop: Double(viewport.safeTop),
            safeBottom: Double(viewport.safeBottom),
            headerBottom: headerBottom.map { Double($0) },
            composerTop: bottomControlsTop > 0 ? Double(bottomControlsTop) : nil,
            keyboardTop: keyboardTop.map { Double($0) }
        )
        let rows = reads.rows.compactMap { id, frame in
            viewModel.rowOrder(of: id).map {
                ReadRowFrame(id: id, order: $0, minY: Double(frame.minY), height: Double(frame.height))
            }
        }
        let report = TranscriptReadReport(newest: ReadVisibility.newestSeen(rows, in: area), atBottom: bottom.atBottom)
        if let area = visibleArea {
            // Choose a row whose current placement can be represented by a normal scroll anchor.
            for (id, frame) in reads.rows.sorted(by: { $0.value.minY < $1.value.minY }) {
                guard frame.maxY > area.minY, frame.minY < area.maxY else { continue }
                let available = area.height - frame.height
                guard abs(available) > 1 else { continue }
                let anchor = Double((frame.minY - area.minY) / available)
                if (0...1).contains(anchor) { reads.place = (id, anchor); break }
            }
        }
        guard report != reads.reported else { return }
        reads.reported = report
        viewModel.noteVisible(newestSeen: report.newest, atBottom: report.atBottom)
    }

    // MARK: История

    /// Старое ложится сверху, а верхнее сообщение остаётся на месте (`follow`). Страница не
    /// пришла (пауза сервера после too.many.requests, сеть), а верх всё ещё на экране — она
    /// спрашивается снова через 3, 6 и 12 секунд: раньше лента молча вставала до новой прокрутки.
    private func loadOlderFromTop() async {
        var failures = 0
        while (headerVisible || nearTopActive) && !Task.isCancelled {
            guard !viewModel.messages.isEmpty, !viewModel.isLoadingOlder,
                  !viewModel.isRestoringHistory, !isOpening, viewModel.canLoadOlder else { return }
            let oldest = viewModel.messages.first?.id
            await viewModel.loadOlder()
            if Task.isCancelled { return }
            if viewModel.olderFailed {
                guard failures < 3 else { return }
                do { try await Task.sleep(for: .seconds(3 << failures)) } catch { return }
                failures += 1
                continue
            }
            failures = 0
            // Allow the repository stream and layout to publish the new page.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            // An empty/overlapping page must not create an unbounded request loop.
            guard viewModel.messages.first?.id != oldest else { return }
        }
    }

    // MARK: Прокрутка

    /// Верх клавиатуры, если она выше поля ввода: им закрыт низ ленты.
    private var composerCover: CGFloat? {
        let candidates = [bottomControlsTop > 0 ? bottomControlsTop : nil, keyboardTop].compactMap { $0 }
        return candidates.min()
    }

    private var visiblePlace: String? {
        guard let area = visibleArea else { return nil }
        return reads.rows.filter { $0.value.maxY > area.minY && $0.value.minY < area.maxY }
            .min { $0.value.minY < $1.value.minY }?.key
    }

    private var visibleArea: CGRect? {
        guard let viewport = reads.viewport else { return nil }
        let area = ReadVisibility.area(
            viewport: ReadSpan(minY: Double(viewport.frame.minY), maxY: Double(viewport.frame.maxY)),
            safeTop: Double(viewport.safeTop), safeBottom: Double(viewport.safeBottom),
            headerBottom: headerBottom.map { Double($0) },
            composerTop: bottomControlsTop > 0 ? Double(bottomControlsTop) : nil,
            keyboardTop: keyboardTop.map { Double($0) }
        )
        return CGRect(x: 0, y: area.minY, width: 1, height: area.maxY - area.minY)
    }

    /// Верх области прокрутки: рамка ленты плюс её верхний безопасный отступ.
    private var contentTop: CGFloat {
        guard let viewport = reads.viewport else { return 0 }
        // Измеренная шапка — настоящий край; отступ рамки к ней не прибавляется (`ReadVisibility.area`).
        if let headerBottom { return max(viewport.frame.minY, headerBottom) }
        return viewport.frame.minY + max(0, viewport.safeTop)
    }

    private func measuredGeometry() {
        guard let area = visibleArea else { return }
        let last = viewModel.rows.last.flatMap { reads.rows[$0.id] }
        let first = viewModel.rows.first.flatMap { reads.rows[$0.id] }
        // Вся лента помещается: первая строка не ушла выше верха ленты. Верх — край самой
        // прокрутки, а не низ шапки: короткая лента стоит сразу под шапкой и частью заходит
        // под её стекло, и прежняя проверка по шапке держала кнопку «вниз» в коротком чате.
        let fits = first.map { $0.minY >= contentTop - 2 } ?? false
        var next = bottom
        next.measuredLastRow(minY: last.map { Double($0.minY) }, maxY: last.map { Double($0.maxY) },
            viewportMin: Double(area.minY), viewportMax: Double(area.maxY), userScrolling: userScrolling, contentFits: fits,
            buttonMin: Double(contentTop))
        if next != bottom { bottom = next }
    }

    private func requestLatest() {
        guard let id = viewModel.rows.last?.id else { return }
        bottom.beginFollowing()
        scroll.start(id: id, anchor: 1, latest: true)
    }

    private func requestHistory(_ id: String, anchor: Double) {
        bottom.beginReadingHistory()
        scroll.start(id: id, anchor: anchor, latest: false)
    }

    /// Choose once per appearance: a later server response cannot replace a cache target.
    private func openAtStart() {
        guard !openingTargetChosen, !viewModel.rows.isEmpty else { return }
        if viewModel.hasPendingOpen {
            if !viewModel.isRestoringHistory { viewModel.startPendingOpen() }
            return
        }
        openingTargetChosen = true
        if let anchor = viewModel.unreadAnchorId {
            recordScroll("open-target=unread:\(anchor)", immediate: true)
            requestHistory(anchor, anchor: 0.12)
        } else if let place = viewModel.restoredPlace {
            recordScroll("open-target=restored:\(place)", immediate: true)
            requestHistory(place, anchor: 0)
        } else {
            recordScroll("open-target=latest", immediate: true)
            requestLatest()
        }
    }

    /// Прилипать к последнему сообщению. Палец и открытие на непрочитанном это отменяют.
    private var stickToBottom: Bool {
        if userScrolling || isOpening || viewModel.isJumped { return false }
        if let request = scroll.request { return request.latest }
        return bottom.followsLatest
    }

    /// Куда встать в этом кадре. Команда прокрутки важнее, иначе — цель открытия.
    private var revealTarget: TranscriptCollectionFeed.Reveal? {
        if let request = scroll.request {
            return .init(id: request.id, anchor: request.anchor, latest: request.latest)
        }
        guard isOpening, !openingTargetChosen, !viewModel.hasPendingOpen, !viewModel.rows.isEmpty else { return nil }
        if let id = viewModel.unreadAnchorId {
            return .init(id: id, anchor: 0.12, latest: false)
        }
        if let id = viewModel.restoredPlace {
            return .init(id: id, anchor: 0, latest: false)
        }
        if let id = viewModel.rows.last?.id {
            return .init(id: id, anchor: 1, latest: true)
        }
        return nil
    }

    private func followCollection() {
        guard !viewModel.rows.isEmpty, viewModel.scrollTarget == nil else { return }
        if isOpening { openAtStart(); return }
        switch viewModel.messagesChange {
        case .prepended, .trimmed, .reload:
            // Снимок коллекции сам держит видимую строку. Вторая команда прокрутки её сдвигает.
            return
        default:
            followShared()
        }
    }

    private func followShared() {
        let preservesPlace: Bool
        switch viewModel.messagesChange {
        case .prepended, .reload, .trimmed: preservesPlace = true
        default: preservesPlace = viewModel.changeFromPaging
        }
        if preservesPlace {
            if !userScrolling, scroll.request == nil, let place = reads.place,
               viewModel.rowOrder(of: place.id) != nil {
                if bottom.followsLatest && !viewModel.isJumped { requestLatest() }
                else { requestHistory(place.id, anchor: place.anchor) }
            }
            return
        }
        guard !viewModel.isJumped else { return }
        if case .appended(let count) = viewModel.messagesChange, count > 0 {
            if bottom.followsLatest || viewModel.messages.suffix(count).contains(where: viewModel.isOutgoing) {
                requestLatest()
            }
        }
    }

    private func goDown() {
        if viewModel.returnFromJump() { return }
        recordScroll("scroll-target=latest", immediate: true)
        requestLatest()
    }

    private func perform(_ target: ChatScrollTarget?) {
        guard let target else { return }
        viewModel.consumeScroll()
        openingTargetChosen = true
        switch target {
        case .message(let id, _): requestHistory(id, anchor: 0.5)
        case .bottom: requestLatest()
        }
    }

    private func applyCollectionFrames(_ frames: [String: CGRect], viewport: CGRect) {
        let oldHeights = Dictionary(uniqueKeysWithValues: reads.rows.map { ($0.key, $0.value.height) })
        reads.rows = frames
        reads.revision += 1
        for (id, _) in frames {
            reads.rowRevisions[id] = reads.revision
        }
        for id in oldHeights.keys where frames[id] == nil {
            reads.rowRevisions[id] = nil
        }
        reads.viewport = TranscriptReadViewport(frame: viewport, safeTop: 0, safeBottom: 0)
        refreshNearTopPrefix()
        measuredGeometry()
        let heightChanged = frames.contains { id, frame in oldHeights[id] != frame.height }
        if heightChanged, !bottom.atBottom, bottom.followsLatest, !userScrolling, !isOpening, scroll.request == nil {
            requestLatest()
        }
        reportReads()
    }

    /// Минимальный индекс строки, пересекающей viewport — для `HistoryPrefetch`.
    private func refreshNearTopPrefix() {
        guard let viewport = reads.viewport else {
            nearTopPrefix = nil
            return
        }
        for (index, row) in viewModel.rows.enumerated() {
            guard let frame = reads.rows[row.id], frame.intersects(viewport.frame) else { continue }
            nearTopPrefix = index
            return
        }
        nearTopPrefix = nil
    }

    /// Признаки низа ленты, за которыми следит `body`.
    private var bottomSignal: [Bool] { [bottom.atBottom, bottom.lastEndVisible] }

    /// Низ живой ленты на экране — прижата к нему или виден конец последнего сообщения:
    /// непрочитанных ниже нет. Во время команды прокрутки не отмечается, после неё — сразу.
    private func noteBottomIfReached() {
        guard !isOpening, scroll.request == nil, bottom.atBottom || bottom.lastEndVisible else { return }
        viewModel.noteAtBottom()
    }

    // MARK: Значения пузыря

    private func state(for row: TranscriptRow, width: CGFloat) -> TranscriptBubble.Snapshot {
        let message = row.message
        let showsAuthors = rules.showsAuthors
        let reacts = viewModel.reactions.canReact(message)
        let loading = viewModel.attachments.loadingMediaId.flatMap { id in
            message.content.attachments.contains { $0.id == id } ? id : nil
        }
        let round = viewModel.attachments.roundPlayback.flatMap { playback in
            message.content.visuals.contains { $0.id == playback.id } ? playback : nil
        }
        return TranscriptBubble.Snapshot(
            row: row,
            maxWidth: Self.bubbleMaxWidth(rowWidth: width - Self.feedInset * 2),
            showsAuthorName: showsAuthors && row.showsAuthorName,
            showsAuthorAvatar: showsAuthors && row.showsAuthorAvatar,
            reservesAvatar: showsAuthors,
            allowsComments: allowsComments(message),
            canWrite: rules.writable,
            showsReactionUsers: rules.showsReactionUsers,
            isRevealed: reveal.isRevealed(message.id),
            highlighted: viewModel.highlightedId == message.id,
            phase: message.content.voices.first.map { viewModel.voices.phase(for: $0.id) } ?? .idle,
            loadingId: loading,
            commentCount: viewModel.comments.count(for: message),
            uploadProgress: viewModel.uploadFraction(of: message),
            reacts: reacts,
            quickReactions: reacts ? viewModel.reactions.quickReactions(for: message) : [],
            canEdit: viewModel.composer.canEdit(message),
            savesToPhotos: viewModel.attachments.canSave(message, to: .photos),
            savesToFiles: viewModel.attachments.canSave(message, to: .files),
            roundPlayback: round,
            transcript: message.content.voices.first.map { viewModel.transcripts.phase(for: $0) } ?? .collapsed,
            canTranscribe: viewModel.transcripts.canTranscribe(message),
            quickReaction: quickReaction,
            chatType: rules.kind,
            showsInfo: viewModel.canShowInfo(message),
            isSelecting: viewModel.selection.isActive,
            isSelected: viewModel.selection.isSelected(message.id),
            selectable: viewModel.selection.canSelect(message)
        )
    }

    /// Кнопка комментариев — только под постами канала с включёнными родными комментариями
    /// (опция `COMMENTS: true`, как в Komet). Без опции их нет: обсуждение такого канала, если
    /// оно есть, ведёт бот кнопкой под постом.
    private func allowsComments(_ message: Message) -> Bool {
        rules.allowsComments
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

/// Что лента знает о видимых строках для отметки прочтения. Класс, а не состояние: рамки
/// меняются каждый кадр прокрутки, а перерисовывать из-за них ленту не нужно.
@MainActor
final class TranscriptReadTracker {
    /// Рамки показанных строк в глобальных координатах, по id сообщения.
    var rows: [String: CGRect] = [:]
    var revision = 0
    var rowRevisions: [String: Int] = [:]
    var place: (id: String, anchor: Double)?
    var viewport: TranscriptReadViewport?
    /// Последнее, что ушло в модель.
    var reported: TranscriptReadReport?
}

/// Рамка ленты в глобальных координатах и её безопасные отступы сверху и снизу.
struct TranscriptReadViewport: Equatable, Sendable {
    var frame: CGRect
    var safeTop: CGFloat
    var safeBottom: CGFloat
}

/// Самое новое увиденное сообщение и лента ли у низа: то, что получает модель.
struct TranscriptReadReport: Equatable {
    var newest: String?
    var atBottom: Bool
}

/// Круглая кнопка перехода на стекле: «вниз» с числом непрочитанных ниже или «@» с числом
/// непрочитанных упоминаний — бейджем.
private struct ChatJumpButton: View {
    enum Content {
        case down
        case mention
    }

    let content: Content
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .foregroundStyle(.primary)
                .maxlyGlassCircle(size: ChatControlMetrics.diameter)
                .overlay(alignment: .top) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.app(.caption2, .bold).monospacedDigit())
                            .foregroundStyle(Color.maxlyOnAccent)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.maxlyAccent, in: Capsule())
                            .offset(y: -10)
                            .contentTransition(.numericText())
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        switch content {
        case .down:
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
        case .mention:
            Text(verbatim: "@")
                .font(.system(size: 19, weight: .semibold))
        }
    }

    private var accessibilityText: String {
        switch content {
        case .down: count > 0 ? "Вниз, новых сообщений: \(count)" : "Вниз"
        case .mention: "Непрочитанные упоминания: \(count)"
        }
    }
}

/// Плашка пустого «Избранного», как в Max: знак закладки и что сюда сохранять.
private struct SavedMessagesPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.maxlyOnAccent)
                .frame(width: 64, height: 64)
                .background(Color.maxlyAccent, in: Circle())
            Text("Это избранное")
                .font(.app(.headline))
            Text("Сохраняйте сообщения, медиа и файлы — доступ будет только у вас")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: 360)
        .maxlyGlassRounded(radius: 24)
        .accessibilityElement(children: .combine)
    }
}

/// Плашка даты верхних сообщений поверх ленты, пока лента едет, и чуть после остановки.
/// Только iOS 18: на iOS 17 нет ни видимых строк, ни фазы прокрутки — там даты видны
/// разделителями в ленте. Состояние живёт в модификаторе: прокрутка не пересобирает ленту.
private struct FloatingDayOverlay: ViewModifier {
    let model: ChatViewModel
    /// Верх ленты на экране: плашка легла бы на загрузчик истории.
    let topVisible: Bool
    /// Отступ от верха ленты. Лента чата рисуется под шапкой, и плашка должна начинаться ниже неё.
    var topPadding: CGFloat = 8
    @State private var topRowId: String?
    @State private var scrolling = false
    @State private var shown = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.3) { ids in
                    let top = model.topRow(among: ids)
                    if top != topRowId { topRowId = top }
                }
                .onScrollPhaseChange { _, phase in
                    let moving = phase != .idle
                    if moving != scrolling { scrolling = moving }
                }
                .overlay(alignment: .top) {
                    ZStack {
                        // У верхней строки свой разделитель даты — плашка его только повторила бы.
                        if shown, !topVisible, !model.rowShowsDay(topRowId), let day = model.dayTitle(ofRow: topRowId) {
                            FloatingDayPill(title: day)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, topPadding)
                    .allowsHitTesting(false)
                    .animation(MaxlyMotion.fade, value: shown)
                }
                .task(id: scrolling) {
                    if scrolling {
                        shown = true
                    } else if shown {
                        try? await Task.sleep(for: .milliseconds(1200))
                        if !Task.isCancelled { shown = false }
                    }
                }
        } else {
            content
        }
    }
}

/// Дата верхних сообщений поверх ленты, пока она едет.
private struct FloatingDayPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.app(.footnote, .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .maxlyGlassCapsule()
    }
}
