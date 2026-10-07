import SwiftUI
import UIKit
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Лента чата: пузыри, разделители дней, подгрузка истории, кнопка «вниз» и удержание низа.
///
/// Положение как в Telegram: чат открывается на первом непрочитанном или там, где читатель
/// остался; старое подгружается само, когда показался верх ленты; переход к цитате, закрепу
/// или найденному сообщению ведёт к нему, даже если оно далеко в истории (модель приносит окно
/// вокруг него), а кнопка «вниз» сначала возвращает к сообщению, с которого перешли.
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
    /// Верх ленты на экране: не пришедшая страница старого спрашивается снова, пока он виден.
    @State private var headerVisible = false
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
                        newerLoader
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
                .modifier(TranscriptBottomTracking(
                    bottom: $bottom,
                    viewportHeight: geo.size.height,
                    anchorsBottom: bottom.atBottom && !viewModel.isJumped
                ))
                .modifier(FloatingDayOverlay(model: viewModel))
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
                .animation(OrbitleMotion.fade, value: viewModel.showsSavedPlaceholder)
                .overlay(alignment: .bottomTrailing) {
                    Group {
                        if bottom.showsButton(hasMessages: !viewModel.messages.isEmpty) || viewModel.isJumped {
                            ScrollDownButton(unseen: viewModel.unreadBelow) { goDown(proxy) }
                                .padding(.trailing, ChatControlMetrics.trailingInset)
                                .padding(.bottom, 10)
                                .transition(.orbitlePop(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: bottom.atBottom)
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.unreadBelow)
                }
                .onChange(of: viewModel.scrollToken) { _, _ in perform(viewModel.scrollTarget, proxy: proxy) }
                // Строка у низа экрана: до неё всё прочитано, счётчик «вниз» уменьшается.
                .onChange(of: position) { _, id in
                    guard !isOpening else { return }
                    viewModel.noteBottomVisible(id)
                }
                .onChange(of: bottom.atBottom) { _, atBottom in
                    if atBottom, !isOpening { viewModel.noteAtBottom() }
                }
                .onAppear {
                    // Просьба прокрутки от прошлого захода к этому открытию не относится. Пришедшая,
                    // пока лента была скрыта (профиль), выполняется сейчас: иначе она держала бы `follow`.
                    if isOpening { viewModel.consumeScroll() } else { perform(viewModel.scrollTarget, proxy: proxy) }
                }
                .onDisappear { viewModel.savePlace(position, atBottom: bottom.atBottom) }
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
        } else if !viewModel.messages.isEmpty && viewModel.canLoadOlder {
            // Старое подгружается само, когда верх ленты показался: как в Telegram, без кнопки.
            ZStack {
                if viewModel.isLoadingOlder { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .onAppear {
                headerVisible = true
                loadOlderFromTop()
            }
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
    private func loadOlderFromTop(attempt: Int = 0) {
        guard !viewModel.messages.isEmpty, !viewModel.isLoadingOlder, !viewModel.isRestoringHistory, !isOpening else { return }
        olderAnchor = viewModel.messages.first?.id
        Task {
            await viewModel.loadOlder()
            guard viewModel.olderFailed, attempt < 3 else { return }
            try? await Task.sleep(for: .seconds(3 << attempt))
            if headerVisible { loadOlderFromTop(attempt: attempt + 1) }
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
        // Чат открыт на найденном сообщении: переход к нему ставит ленту сам, когда история сверена.
        if viewModel.hasPendingOpen {
            bottom.beginReadingHistory()
            if !viewModel.isRestoringHistory { viewModel.startPendingOpen() }
            return
        }
        if let anchor = viewModel.unreadAnchorId {
            bottom.beginReadingHistory()
            proxy.scrollTo(anchor, anchor: UnitPoint(x: 0.5, y: 0.12))
        } else if let place = viewModel.restoredPlace {
            // Вернулись в чат, из которого ушли посреди истории, — на то же место.
            bottom.beginReadingHistory()
            position = place
        } else {
            position = viewModel.messages.last?.id
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard !viewModel.messages.isEmpty else { return }
        // Модель просит прокрутку (переход, возврат): ленту ставит она, а не смена состава.
        if viewModel.scrollTarget != nil { return }
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
        // Страницы окна перехода — история, а не новое в чате: лента стоит на месте.
        if viewModel.changeFromPaging || viewModel.isJumped { return }
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
        }
        // Иначе чужое ждёт ниже: число на кнопке «вниз» считает модель (`unreadBelow`).
    }

    /// Кнопка «вниз»: назад к сообщению, с которого перешли к цитате, или из окна перехода к
    /// живой ленте (это просит модель), иначе — к последнему сообщению.
    private func goDown(_ proxy: ScrollViewProxy) {
        if viewModel.returnFromJump() { return }
        scrollToLatest(proxy)
    }

    /// Просьба модели: к сообщению посередине экрана или вниз после выхода из окна перехода.
    /// Лента ленивая: строки вокруг цели измеряются в пути, поэтому на следующем проходе
    /// цикла прокрутка повторяется уже по измеренным строкам.
    private func perform(_ target: ChatScrollTarget?, proxy: ScrollViewProxy) {
        guard let target else { return }
        viewModel.consumeScroll()
        switch target {
        case .message(let id, _):
            bottom.beginReadingHistory()
            center(id, proxy)
            Task { @MainActor in
                await Task.yield()
                center(id, proxy)
            }
        case .bottom:
            let jump = bottom.beginJump()
            jumpToBottom(proxy)
            Task { @MainActor in
                await Task.yield()
                guard bottom.finishJump(jump) else { return }
                jumpToBottom(proxy)
            }
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

    private func center(_ id: String, _ proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { proxy.scrollTo(id, anchor: .center) }
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
                .orbitleGlassCircle(size: ChatControlMetrics.diameter)
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
    /// Держать низ при росте содержимого: лента внизу живой ленты. В окне перехода страницы
    /// новее ложатся под экран, и лента стоит на месте.
    let anchorsBottom: Bool
    @State private var dragging = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(anchorsBottom ? .bottom : .top, for: .sizeChanges)
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

/// Плашка даты верхних сообщений поверх ленты, пока лента едет, и чуть после остановки, как в
/// Telegram. Только iOS 18: на iOS 17 нет ни видимых строк, ни фазы прокрутки — там даты видны
/// разделителями в ленте. Состояние живёт в модификаторе: прокрутка не пересобирает ленту.
private struct FloatingDayOverlay: ViewModifier {
    let model: ChatViewModel
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
                        if shown, let day = model.dayTitle(ofRow: topRowId) {
                            FloatingDayPill(title: day)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .animation(OrbitleMotion.fade, value: shown)
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

/// Дата верхних сообщений поверх ленты, пока она едет, как в Telegram.
private struct FloatingDayPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .orbitleGlassCapsule()
    }
}
