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
/// Движок ленты: `TranscriptFeedEngine` — по умолчанию `UICollectionView`
/// (`TranscriptCollectionFeed`), запасной путь — `LazyVStack`. План A–D:
/// `docs/telegram-smoothness.md`.
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
    @State private var geometrySampler = TranscriptGeometrySampler()
    @State private var heightCache = BubbleHeightCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatWallpaper) private var wallpaper

    static let feedInset: CGFloat = 8
    static let prefetchCount = 40
    /// Декод картинок под пузырь (~ширина экрана × bubbleMax × 2× scale).
    static let prefetchMaxPixel = 900

    var body: some View {
        GeometryReader { geo in
            Group {
                switch TranscriptFeedEngine.kind {
                case .collection:
                    collectionFeed(width: geo.size.width)
                case .lazyStack:
                    lazyStackFeed(width: geo.size.width)
                }
            }
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
                Group {
                    if !isOpening && !viewModel.messages.isEmpty && (downButton.shown || viewModel.isJumped) {
                        ScrollDownButton(unseen: viewModel.unreadBelow) { goDown() }
                            .padding(.trailing, ChatComposer.trailingInset(canWrite: canWrite))
                            .padding(.bottom, 10)
                            .transition(.maxlyPop(reduceMotion: reduceMotion))
                    }
                }
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: downButton.shown)
                .animation(MaxlyMotion.quick(reduceMotion: reduceMotion), value: viewModel.unreadBelow)
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
                heightCache.removeAll()
            }
            .onChange(of: geo.size.height) { _, _ in
                guard bottom.followsLatest, !userScrolling, !isOpening else { return }
                requestLatest()
            }
            .task(id: viewModel.transcriptVersion) {
                let urls = Self.prefetchURLs(viewModel.messages.suffix(Self.prefetchCount))
                guard !urls.isEmpty else { return }
                await ImagePipeline.shared.prefetchDecoded(urls.map { ($0, Self.prefetchMaxPixel) })
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
    private func collectionFeed(width: CGFloat) -> some View {
        TranscriptCollectionFeed(
            viewModel: viewModel,
            rows: viewModel.rows,
            width: width,
            reveal: reveal,
            feedInset: Self.feedInset,
            reduceMotion: reduceMotion,
            animateInserts: bottom.atBottom && !viewModel.isRestoringHistory,
            isOpening: isOpening,
            isRestoringHistory: viewModel.isRestoringHistory,
            scrollRequest: scroll.request,
            canLoadOlder: viewModel.canLoadOlder,
            isLoadingOlder: viewModel.isLoadingOlder,
            isJumped: viewModel.isJumped,
            emptyHint: viewModel.emptyHint,
            showsChannelReady: viewModel.latestLoaded && viewModel.messages.isEmpty && !viewModel.isRestoringHistory
                && viewModel.historyError == nil && !viewModel.showsSavedPlaceholder && chatType == .channel && canWrite,
            showsEmpty: viewModel.latestLoaded && viewModel.messages.isEmpty && !viewModel.isRestoringHistory
                && viewModel.historyError == nil && !viewModel.showsSavedPlaceholder,
            snapshot: { state(for: $0, width: width) },
            onAuthor: onAuthor,
            onFrames: { frames, viewport, _ in
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
            onTopVisible: { headerVisible = $0 },
            onNearTopPrefix: { nearTopPrefix = $0 },
            onLoadNewer: { Task { await viewModel.loadNewer() } },
            onScrollFinished: { token, confirmed in
                guard scroll.finish(token) else { return }
                isOpening = false
                if !confirmed { bottom.beginReadingHistory() }
                recordScroll(confirmed ? "scroll-confirmed" : "scroll-unconfirmed", immediate: true)
                noteBottomIfReached()
                reportReads()
            }
        )
        .modifier(FloatingDayOverlay(model: viewModel, topVisible: headerVisible))
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

    @ViewBuilder
    private func lazyStackFeed(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    header(proxy)
                    ForEach(viewModel.rows) { row in
                        let estimate = heightCache.estimated(
                            for: row,
                            maxWidth: Double(min(520, max(0, width - Self.feedInset * 2) * MaxlyTheme.bubbleMax))
                        )
                        TranscriptBubble(
                            state: state(for: row, width: width),
                            viewModel: viewModel,
                            reveal: reveal,
                            onAuthor: onAuthor
                        )
                        .equatable()
                        .frame(minHeight: CGFloat(estimate), alignment: .top)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            let old = reads.rows[row.id]
                            reads.rows[row.id] = frame
                            reads.revision += 1
                            reads.rowRevisions[row.id] = reads.revision
                            heightCache.store(id: row.id, height: Double(frame.height))
                            sampleLazyGeometry(force: false) {
                                refreshNearTopPrefix()
                                measuredGeometry()
                                if old?.height != frame.height, !bottom.atBottom,
                                   bottom.followsLatest, !userScrolling, !isOpening, scroll.request == nil {
                                    requestLatest()
                                }
                                reportReads()
                                if row.id == viewModel.rows.last?.id { recordScroll("last-row-geometry") }
                            }
                        }
                        .onDisappear {
                            reads.rows[row.id] = nil
                            reads.revision += 1
                            reads.rowRevisions[row.id] = nil
                            sampleLazyGeometry(force: true) {
                                measuredGeometry()
                                reportReads()
                            }
                        }
                        .id(row.id)
                        .transition(.maxlyComposerFlight(outgoing: row.isOutgoing, reduceMotion: reduceMotion))
                    }
                    newerLoader
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
                .background {
                    TranscriptScrollObserver(diagnostics: diagnostics) { distance, visible in
                        var next = downButton
                        if next.update(distance: distance, visibleHeight: visible) { downButton = next }
                    }
                    .frame(width: 0, height: 0)
                }
                .animation(
                    bottom.atBottom && !viewModel.isRestoringHistory
                        ? MaxlyMotion.transcript(viewModel.messagesChange, reduceMotion: reduceMotion) : nil,
                    value: viewModel.transcriptVersion
                )
            }
            .onGeometryChange(for: TranscriptReadViewport.self) { proxy in
                TranscriptReadViewport(
                    frame: proxy.frame(in: .global),
                    safeTop: proxy.safeAreaInsets.top,
                    safeBottom: proxy.safeAreaInsets.bottom
                )
            } action: { viewport in
                reads.viewport = viewport
                reads.revision += 1
                sampleLazyGeometry(force: false) {
                    measuredGeometry()
                    reportReads()
                    recordScroll("viewport")
                }
            }
            .coordinateSpace(name: "transcript-viewport")
            .modifier(TranscriptInteractionTracking { moving, takeover in
                userScrolling = moving
                if takeover {
                    scroll.cancel()
                    bottom.userTookOver()
                    openingTargetChosen = true
                    isOpening = false
                    recordScroll("scroll-cancel=user", immediate: true)
                }
                measuredGeometry()
            })
            .task(id: scroll.request?.token) {
                guard let request = scroll.request else { return }
                await execute(request, proxy: proxy)
            }
            .modifier(FloatingDayOverlay(model: viewModel, topVisible: headerVisible))
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded { focus.wrappedValue = false },
                including: focus.wrappedValue ? .all : .subviews
            )
            .onChange(of: viewModel.transcriptVersion, initial: true) { _, _ in
                recordScroll("transcript-change", immediate: true)
                follow(proxy)
            }
            .onChange(of: viewModel.isRestoringHistory) { _, restoring in
                recordScroll("restoring-\(restoring)", immediate: true)
                guard !restoring else { return }
                if isOpening { openAtStart(proxy) }
            }
        }
    }

    /// Global row frames and viewport use the same coordinate system. A missing
    /// last frame is useful too: LazyVStack has not materialized that row.
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

    // MARK: Шапка и низ

    /// Свой канал без постов, как в Max: «Канал готов» и подсказка.
    private var channelReady: some View {
        VStack(spacing: 10) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.maxlyAccent, in: Circle())
            Text("Канал готов")
                .font(.app(.headline))
            Text("Добавляйте посты и приглашайте подписчиков")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 32)
        .padding(.top, 80)
    }

    @ViewBuilder
    private func header(_ proxy: ScrollViewProxy) -> some View {
        if let hint = viewModel.emptyHint {
            VStack(spacing: 12) {
                MaxlyMark(size: 56)
                    .foregroundStyle(.tertiary)
                Text(hint)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 80)
        } else if viewModel.latestLoaded && viewModel.messages.isEmpty && !viewModel.isRestoringHistory && viewModel.historyError == nil && !viewModel.showsSavedPlaceholder {
            if chatType == .channel && canWrite {
                channelReady
            } else {
                Text("Здесь пока нет сообщений")
                    .foregroundStyle(.secondary)
                    .padding(24)
            }
        } else if !viewModel.messages.isEmpty && viewModel.canLoadOlder {
            // Старое подгружается само, когда верх ленты показался, без кнопки.
            ZStack {
                if viewModel.isLoadingOlder { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .overlay {
                if !viewModel.isLoadingOlder {
                    Button("Загрузить предыдущие сообщения") { Task { await loadOlderFromTop() } }
                        .font(.app(.caption))
                }
            }
            .onGeometryChange(for: Bool.self) { geometry in
                let frame = geometry.frame(in: .named("transcript-viewport"))
                return frame.maxY >= 0 && frame.minY < 100
            } action: { visible in headerVisible = visible }
            .onDisappear { headerVisible = false }
        }
    }

    /// Низ окна перехода: страница новее грузится, когда он показался. Дойдя до живой ленты,
    /// окно сливается с ней, и загрузчик уходит.
    @ViewBuilder
    private var newerLoader: some View {
        if viewModel.isJumped {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .onAppear { Task { await viewModel.loadNewer() } }
        }
    }

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

    /// Метка низа ленты: видна — значит, пользователь внизу (iOS 17).
    // MARK: Прокрутка

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
    private func openAtStart(_ proxy: ScrollViewProxy? = nil) {
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
        _ = proxy
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard !viewModel.rows.isEmpty, viewModel.scrollTarget == nil else { return }
        if isOpening { openAtStart(proxy); return }
        followShared()
    }

    private func followCollection() {
        guard !viewModel.rows.isEmpty, viewModel.scrollTarget == nil else { return }
        if isOpening { openAtStart(); return }
        followShared()
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
        for (id, frame) in frames {
            reads.rowRevisions[id] = reads.revision
            heightCache.store(id: id, height: Double(frame.height))
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

    private func sampleLazyGeometry(force: Bool, _ work: () -> Void) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard geometrySampler.shouldFire(nowNs: now, force: force) else { return }
        work()
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

    /// The only writer of scroll position. No empty sentinel, UIKit offset writes or
    /// sizeChanges anchor competes with this command. Corrections require fresh row geometry.
    @MainActor private func execute(_ request: TranscriptScrollController.Request, proxy: ScrollViewProxy) async {
        await Task.yield()
        guard !Task.isCancelled, scroll.request?.token == request.token else { return }
        func apply() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(request.id, anchor: UnitPoint(x: 0.5, y: request.anchor))
            }
        }
        recordScroll("scroll-request:\(request.id)", immediate: true)
        apply()
        var correctedRevision = reads.rowRevisions[request.id] ?? 0
        var corrections = 0
        var settledSamples = 0
        for _ in 0..<24 {
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            guard !Task.isCancelled, scroll.request?.token == request.token else { return }
            if let row = reads.rows[request.id], let area = visibleArea {
                measuredGeometry()
                let reached = request.latest && request.id == viewModel.rows.last?.id && (bottom.atBottom || bottom.lastEndVisible) || TranscriptScrollController.reached(
                    anchor: request.anchor, rowMin: Double(row.minY), rowMax: Double(row.maxY),
                    viewportMin: Double(area.minY), viewportMax: Double(area.maxY))
                settledSamples = reached ? settledSamples + 1 : 0
                if settledSamples >= 2 {
                    guard scroll.finish(request.token) else { return }
                    isOpening = false
                    recordScroll("scroll-confirmed:\(request.id)", immediate: true)
                    // Пока шла команда, низ не отмечался: смена `atBottom` пришлась на неё.
                    noteBottomIfReached()
                    reportReads()
                    return
                }
                if !reached, let revision = reads.rowRevisions[request.id], revision != correctedRevision, corrections < 2 {
                    correctedRevision = revision
                    corrections += 1
                    recordScroll("scroll-correction=measured:\(request.id)", immediate: true)
                    apply()
                }
            }
        }
        guard scroll.finish(request.token) else { return }
        isOpening = false
        bottom.beginReadingHistory()
        recordScroll("scroll-unconfirmed:\(request.id)", immediate: true)
        noteBottomIfReached()
        reportReads()
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
            maxWidth: min(520, max(0, width - Self.feedInset * 2) * MaxlyTheme.bubbleMax),
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
            quickReaction: quickReaction,
            chatType: chatType,
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

/// Круглая кнопка «вниз» на стекле; число непрочитанных, пришедших сверху, — бейджем.
private struct ScrollDownButton: View {
    let unseen: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .maxlyGlassCircle(size: ChatControlMetrics.diameter)
                .overlay(alignment: .top) {
                    if unseen > 0 {
                        Text(unseen > 99 ? "99+" : "\(unseen)")
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
        .accessibilityLabel(unseen > 0 ? "Вниз, новых сообщений: \(unseen)" : "Вниз")
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

/// User interaction cancels the one active scroll request on all supported OS versions.
private struct TranscriptInteractionTracking: ViewModifier {
    let changed: (Bool, Bool) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                changed(phase == .tracking || phase == .interacting || phase == .decelerating,
                    phase == .tracking || phase == .interacting)
            }
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 2)
                .onChanged { _ in changed(true, true) }
                .onEnded { _ in changed(false, false) })
        }
    }
}

/// Read-only UIKit geometry observer. It must never fight SwiftUI's scroll command.
private struct TranscriptScrollObserver: UIViewRepresentable {
    let diagnostics: TranscriptDiagnostics
    /// Расстояние от видимого низа до конца ленты и высота видимой части, в точках.
    var onBottomDistance: (Double, Double) -> Void = { _, _ in }
    func makeUIView(context: Context) -> GuardView {
        let view = GuardView()
        view.diagnostics = diagnostics
        view.onBottomDistance = onBottomDistance
        return view
    }
    func updateUIView(_ view: GuardView, context: Context) {
        view.diagnostics = diagnostics
        view.onBottomDistance = onBottomDistance
        view.attachIfNeeded()
    }

    final class GuardView: UIView {
        weak var diagnostics: TranscriptDiagnostics?
        var onBottomDistance: (Double, Double) -> Void = { _, _ in }
        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var scheduled = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                diagnostics?.detach()
                observations = []
                scrollView = nil
                return
            }
            attachIfNeeded()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
            schedule()
        }

        func attachIfNeeded() {
            guard window != nil, scrollView == nil, let found = enclosingScrollView() else { return }
            scrollView = found
            diagnostics?.attach(found)
            // Касание статус-бара или пустого места панели навигации (рядом с кнопками шапки)
            // система превращает в прокрутку к началу. Ленте чата это не нужно: она уезжала к
            // самым старым загруженным сообщениям.
            found.scrollsToTop = false
            // Изменения приходят на главном потоке: их делает UIKit или SwiftUI.
            observations = [
                found.observe(\.contentSize) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
                found.observe(\.contentOffset) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
                found.observe(\.bounds) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
                found.observe(\.contentInset) { [weak self] _, _ in MainActor.assumeIsolated { self?.schedule() } },
            ]
            schedule()
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView { return scroll }
                view = current.superview
            }
            return nil
        }

        /// Проверка — после того как SwiftUI закончит раскладку этого прохода.
        private func schedule() {
            guard !scheduled else { return }
            scheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.sample()
            }
        }

        private func sample() {
            // SwiftUI может вернуть свойство при пересборке прокрутки.
            if scrollView?.scrollsToTop == true { scrollView?.scrollsToTop = false }
            guard let scrollView, scrollView.window != nil else { return }
            let inset = scrollView.adjustedContentInset
            let distance = ScrollDownVisibility.distanceFromBottom(
                contentHeight: Double(scrollView.contentSize.height), offsetY: Double(scrollView.contentOffset.y),
                viewportHeight: Double(scrollView.bounds.height),
                insetTop: Double(inset.top), insetBottom: Double(inset.bottom))
            onBottomDistance(distance, Double(scrollView.bounds.height - inset.top - inset.bottom))
            diagnostics?.record("scroll-geometry")

        }
    }
}

/// Плашка даты верхних сообщений поверх ленты, пока лента едет, и чуть после остановки.
/// Только iOS 18: на iOS 17 нет ни видимых строк, ни фазы прокрутки — там даты видны
/// разделителями в ленте. Состояние живёт в модификаторе: прокрутка не пересобирает ленту.
private struct FloatingDayOverlay: ViewModifier {
    let model: ChatViewModel
    /// Верх ленты на экране («Загрузить предыдущие»): плашка легла бы на кнопку.
    let topVisible: Bool
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
                    .padding(.top, 8)
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
