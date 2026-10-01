import SwiftUI
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
    var canWrite = true
    var isMuted = false
    var onToggleMute: (() -> Void)?
    /// Контакты для вкладки «Контакт» листа вложений. `nil` — вкладка пустая.
    var contactList: (() -> AsyncStream<[Contact]>)? = nil
    /// Модель профиля чата для перехода по нажатию на заголовок.
    var makeProfile: (() -> ChatProfileViewModel?)?
    @State private var forwardList: [ChatListItem] = []
    @State private var attachmentsShown = false
    @State private var recording = RecordingSession()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    /// Низ ленты виден. Пока он виден, новые сообщения прокручивают ленту сами.
    @State private var atBottom = true
    /// Сообщения, пришедшие, пока лента прокручена вверх: число на кнопке «вниз».
    @State private var unseen = 0
    @State private var visibleMessageId: String?
    @State private var isOpening = true
    private static let bottomId = "transcript-bottom"
    /// Отступ ленты от краёв: пузыри ближе к краю экрана.
    private static let feedInset: CGFloat = 8
    /// Отступ поля ввода от краёв.
    private static let composerInset: CGFloat = 12
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Приватный режим: пузыри закрыты заглушкой или размытием, касание открывает на время.
    @Environment(\.privateMode) private var privateMode
    @Environment(PrivateModeSettings.self) private var privateModeSettings: PrivateModeSettings?
    @State private var reveal = PrivateModeReveal()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Стекло поля ввода: скрепка перетекает в поле и обратно (iOS 26).
    @Namespace private var composerGlass

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 2) {
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
                            Button("Раньше") { Task { await viewModel.loadOlder() } }
                                .font(.footnote)
                                .padding(.top, 8)
                        }
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            VStack(spacing: 2) {
                                if startsDay(at: index) {
                                    DaySeparator(ChatContentFormat.dayTitle(message.timestamp))
                                        .transition(.opacity)
                                }
                                TranscriptBubble(
                                    message: message,
                                    viewModel: viewModel,
                                    maxWidth: geo.size.width * OrbitleTheme.bubbleMax,
                                    allowsComments: allowsComments(message),
                                    showsAuthorName: showsAuthors && authorName(at: index),
                                    showsAuthorAvatar: showsAuthors && authorAvatar(at: index),
                                    reservesAvatar: showsAuthors,
                                    group: group(at: index),
                                    canWrite: canWrite,
                                    showsReactionUsers: chatType == .group,
                                    reveal: reveal
                                )
                            }
                            .id(message.id)
                            .transition(.orbitleBubble(outgoing: viewModel.isOutgoing(message), reduceMotion: reduceMotion))
                        }
                        // Метка низа ленты: видна — значит, пользователь внизу.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomId)
                            .background {
                                GeometryReader { marker in
                                    Color.clear.preference(key: TranscriptBottomPreference.self,
                                        value: marker.frame(in: .named("transcript-viewport")).maxY)
                                }
                            }

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
                    .animation(atBottom && !viewModel.isRestoringHistory ? OrbitleMotion.transcript(viewModel.messagesChange, reduceMotion: reduceMotion) : nil, value: viewModel.messages.map(\.id))
                    // Реакция или правка меняет размер пузыря: соседи раздвигаются плавно.
                    .animation(viewModel.messagesChange == .none && !viewModel.isRestoringHistory && atBottom ? OrbitleMotion.quick(reduceMotion: reduceMotion) : nil, value: viewModel.contentVersion)
                }
                // Чат открывается сразу внизу, а не сверху до загрузки истории.
                .defaultScrollAnchor(.bottom)
                .scrollPosition(id: $visibleMessageId, anchor: .top)
                .coordinateSpace(name: "transcript-viewport")
                .onPreferenceChange(TranscriptBottomPreference.self) { bottomY in
                    let nearBottom = bottomY.isFinite && bottomY >= 0 && bottomY <= geo.size.height + (atBottom ? 64 : 24)
                    atBottom = nearBottom
                    if nearBottom { unseen = 0 }
                }
                // Клавиатура уходит, когда ленту тянут вниз вслед за пальцем или просто касаются
                // её: касание не мешает кнопкам пузырей, жест срабатывает вместе с ними.
                .scrollDismissesKeyboard(.interactively)
                // Касание ленты прячет клавиатуру. Без клавиатуры жест выключен, чтобы лента
                // не ждала его при каждом касании.
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false }, including: composerFocused ? .all : .subviews)
                .onChange(of: viewModel.messages.map(\.id)) { old, ids in
                    guard !ids.isEmpty else { return }
                    if viewModel.isRestoringHistory || viewModel.messagesChange == .reload || old.isEmpty {
                        if viewModel.isRestoringHistory || old.isEmpty {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                        }
                        return
                    }
                    let previous = Set(old)
                    let added = viewModel.messages.filter { !previous.contains($0.id) }
                    // История сверху, удаление и перестановка не являются новыми сообщениями.
                    guard case .appended = viewModel.messagesChange, !added.isEmpty else { return }
                    if atBottom || added.contains(where: viewModel.isOutgoing) {
                        withAnimation(OrbitleMotion.standard(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(Self.bottomId, anchor: .bottom)
                        }
                    } else {
                        unseen += added.filter { !viewModel.isOutgoing($0) }.count
                    }
                }
                .onChange(of: viewModel.isRestoringHistory) { _, restoring in
                    guard !restoring else { return }
                    isOpening = false
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                }
                .overlay(alignment: .bottom) {
                    if viewModel.showsSavedPlaceholder {
                        savedPlaceholder
                            .padding(.horizontal, OrbitleTheme.pad + 8)
                            .padding(.bottom, 24)
                            .transition(.opacity)
                    }
                }
                .animation(OrbitleMotion.fade, value: viewModel.showsSavedPlaceholder)
                .overlay(alignment: .bottomTrailing) {
                    Group {
                        if !atBottom, !viewModel.messages.isEmpty {
                            scrollDownButton {
                                withAnimation(OrbitleMotion.standard(reduceMotion: reduceMotion)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                                unseen = 0
                            }
                            .padding(.trailing, OrbitleTheme.pad)
                            .padding(.bottom, 10)
                            .transition(.orbitlePop(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: atBottom)
                }
                .onChange(of: viewModel.scrollToken) { _, _ in
                    guard let id = viewModel.scrollTarget else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if privateMode.isMasked { privateModeBanner }
        }
        // Режим включают и выключают и с другого экрана: капсула всё равно выезжает плавно.
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: privateMode)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        // Видимость tab bar управляется стабильным MainTabView.
        // Системный заголовок (и подпись кнопки «назад» следующего экрана) размыть нельзя:
        // в приватном режиме там всегда общее «Личный чат» / «Групповой чат».
        .navigationTitle(shownTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let makeProfile {
                ToolbarItem(placement: .principal) {
                    NavigationLink {
                        ProfileDestination(make: makeProfile)
                    } label: {
                        PrivateText(title, placeholder: maskedTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("\(shownTitle), открыть профиль")
                }
            }
        }
        .sheet(item: $viewModel.openedComments, onDismiss: { viewModel.closeComments() }) { post in
            if let model = viewModel.commentsModel(for: post) {
                CommentsView(model: model) { viewModel.closeComments() }
                    .presentationDragIndicator(.visible)
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
        .sheet(isPresented: $attachmentsShown) {
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
        .sheet(item: $viewModel.reactionUsers) { model in
            // Открывается из открытого пузыря — значит, смотреть его хотят.
            ReactionUsersView(model: model) { viewModel.reactionUsers = nil }
                .environment(\.privateMode, .visible)
        }
        .fullScreenCover(item: $viewModel.viewer) { request in
            MediaViewer(request: request, download: { await viewModel.downloadVideo($0) }) { viewModel.viewer = nil }
                .environment(\.privateMode, .visible)
        }
        .fullScreenCover(item: $viewModel.openedFile) { file in
            FileQuickLook(url: file.url, title: file.name) { viewModel.openedFile = nil }
                .environment(\.privateMode, .visible)
        }
        .overlay {
            if recording.isVideo {
                VideoNoteOverlay(session: recording)
            }
        }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: recording.isVideo)
        .task {
            viewModel.activate()
            recording.onStart = { [viewModel] in viewModel.stopVoice() }
            recording.onRecorded = { [viewModel] draft in
                Task { await viewModel.sendAttachments([draft], caption: "") }
            }
            await viewModel.loadLatest()
        }
        .onDisappear {
            recording.cancel()
            viewModel.deactivate()
            reveal.hideAll()
        }
        // Режим выключили или сменили вид — открытые пузыри снова закрыты при следующем включении.
        .onChange(of: privateMode) { _, _ in reveal.hideAll() }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.notice)
        .confirmationDialog(
            "Удалить сообщение?",
            isPresented: deletionShown,
            titleVisibility: .visible,
            presenting: viewModel.deletionCandidate
        ) { message in
            if viewModel.deletesWithoutChoice {
                Button("Удалить", role: .destructive) {
                    Task { await viewModel.confirmDelete(message, forEveryone: viewModel.deletesEverywhere(message)) }
                }
            } else {
                if viewModel.canDeleteForEveryone(message) {
                    Button(chatType == .private ? "Удалить у меня и у собеседника" : "Удалить у всех", role: .destructive) {
                        Task { await viewModel.confirmDelete(message, forEveryone: true) }
                    }
                }
                Button("Удалить у меня", role: .destructive) {
                    Task { await viewModel.confirmDelete(message, forEveryone: false) }
                }
            }
            Button("Отмена", role: .cancel) { viewModel.deletionCandidate = nil }
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
        .task(id: viewModel.messages.count) {
            guard !viewModel.messages.isEmpty else { return }
            // Реакции показанных сообщений: история канала их не несёт, а в пушах нет своей
            // реакции, поставленной с другого устройства. Пауза — лента догружается пачками.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            viewModel.requestReactions(for: viewModel.messages)
        }
        .task(id: wantsCommentCounts ? viewModel.messages.count : -1) {
            guard wantsCommentCounts, !viewModel.messages.isEmpty else { return }
            // Пауза: лента догружается пачками, счётчики уходят одним запросом.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            viewModel.requestCommentCounts(for: viewModel.messages)
        }
        // Выбрали сообщение для ответа — клавиатура сразу открывается.
        .onChange(of: viewModel.replyTarget?.id) { _, id in
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

    /// Заголовок для системы: в приватном режиме общий, иначе название чата.
    private var shownTitle: String {
        privateMode.isMasked ? maskedTitle : title
    }

    private var maskedTitle: String {
        PrivateModeMask.chatTitle(type: chatType, isSavedMessages: viewModel.isSavedMessages)
    }

    /// Верх ленты в приватном режиме: стеклянная капсула «Отключить приватный режим»
    /// и подсказка, что сообщение открывается касанием.
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

    /// Плавающий пузырь ввода: капсула поля и кнопка отправки на стекле (iOS 26),
    /// на iOS 17–18 — на материале.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .orbitleGlassCapsule()
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
            if let hint = recording.hint {
                Text(hint)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .orbitleGlassCapsule()
                    .frame(maxWidth: .infinity)
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
            if let notice = viewModel.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .orbitleGlassCapsule()
                    .frame(maxWidth: .infinity)
                    .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
            }
            if let target = viewModel.editTarget {
                editBar(target)
            } else if let reply = viewModel.replyTarget {
                replyBar(reply)
            }
            if canWrite {
                input
            } else {
                readOnlyBar
            }
        }
        .padding(.horizontal, Self.composerInset)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.editTarget?.id)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.replyTarget?.id)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: recording.hint)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.errorMessage)
    }

    /// Поле ввода и кнопка отправки (при правке — галочка).
    private var input: some View {
        VStack(spacing: 0) {
            OrbitleGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    if recording.isActive {
                        RecordingBar(session: recording)
                            .transition(.opacity)
                    }
                    if !recording.isActive {
                        Button {
                            composerFocused = false
                            attachmentsShown = true
                        } label: {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .orbitleGlassCircle(size: 44)
                        .orbitleGlassID("attach", in: composerGlass)
                        // При правке слот сохраняется: длинный текст не получает
                        // дополнительный перенос из-за смены ширины на 52 pt.
                        .opacity(viewModel.editTarget == nil ? 1 : 0)
                        .disabled(viewModel.editTarget != nil)
                        .accessibilityHidden(viewModel.editTarget != nil)
                        .transition(.orbitlePop(reduceMotion: reduceMotion))
                        .accessibilityLabel("Прикрепить")
                    }
                    if !recording.isActive {
                        TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                            .focused($composerFocused)
                            .lineLimit(1...5)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .frame(minHeight: 44)
                            .orbitleGlassRounded(radius: 22)
                            .orbitleGlassID("field", in: composerGlass)
                    }
                    ZStack {
                        if showsRecordButton {
                            RecordButton(session: recording)
                                .transition(.opacity)
                        } else {
                            sendButton.transition(.opacity)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: showsRecordButton)
                }
            }
        }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: recording.isActive)
        // Скрепка прячется при правке и возвращается после неё.
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: viewModel.editTarget == nil)
    }

    /// Кнопка записи видна, пока поле пустое (и не идёт правка) или пока идёт запись.
    private var showsRecordButton: Bool {
        recording.phase != .idle
            || (viewModel.editTarget == nil && viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.send() }
        } label: {
            Image(systemName: viewModel.editTarget == nil ? "arrow.up" : "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .orbitleProminentButtonStyle()
        .buttonBorderShape(.circle)
        .tint(Color.orbitleAccent)
        .disabled(!viewModel.canSend)
        .accessibilityLabel(viewModel.editTarget == nil ? "Отправить" : "Сохранить правку")
    }

    /// Писать нельзя: в канале — кнопка уведомлений, в остальных — пояснение.
    @ViewBuilder
    private var readOnlyBar: some View {
        if chatType == .channel, let onToggleMute {
            Button(action: onToggleMute) {
                Text(isMuted ? "Включить уведомления" : "Выключить уведомления")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.orbitleAccent)
            .orbitleGlassCapsule()
        } else {
            Text(chatType == .channel ? "Писать в канал могут только администраторы" : "В этот чат нельзя отправлять сообщения")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .orbitleGlassCapsule()
        }
    }

    private func editBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orbitleAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Редактирование")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orbitleAccent)
                Text(privateMode.isMasked ? PrivateModeMask.messageText(outgoing: true) : message.text)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.orbitleAccent)
                    .frame(width: 3)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.cancelEdit()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить правку")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .orbitleGlassRounded(radius: 20)
        .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
    }

    private var showsAuthors: Bool { chatType == .group }

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

    /// Круглая кнопка «вниз» на стекле; число непрочитанных, пришедших сверху, — бейджем.
    private func scrollDownButton(action: @escaping () -> Void) -> some View {
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
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unseen > 0 ? "Вниз, новых сообщений: \(unseen)" : "Вниз")
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

    /// Плашка пустого «Избранного», как в Max: знак закладки и что сюда сохранять.
    private var savedPlaceholder: some View {
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

    /// В канале с комментариями счётчики постов спрашиваются у сервера, когда лента меняется.
    private var wantsCommentCounts: Bool {
        chatType == .channel && commentsEnabled != false
    }

    private func startsDay(at index: Int) -> Bool {
        let messages = viewModel.messages
        return ChatContentFormat.startsDay(messages[index].timestamp, after: index > 0 ? messages[index - 1].timestamp : nil)
    }

    private func group(at index: Int) -> BubbleGroup {
        let messages = viewModel.messages
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1] : nil
        let next = index + 1 < messages.count ? messages[index + 1] : nil
        return ChatContentFormat.group(
            authorId: message.authorId,
            date: message.timestamp,
            previous: previous.map { (authorId: $0.authorId, date: $0.timestamp) },
            next: next.map { (authorId: $0.authorId, date: $0.timestamp) }
        )
    }

    private func authorName(at index: Int) -> Bool {
        let messages = viewModel.messages
        let message = messages[index]
        let previous = index > 0 ? messages[index - 1].authorId : nil
        return ChatContentFormat.showsAuthorName(
            outgoing: viewModel.isOutgoing(message),
            authorName: message.authorName,
            authorId: message.authorId,
            previousAuthorId: previous
        )
    }

    private func authorAvatar(at index: Int) -> Bool {
        let messages = viewModel.messages
        let message = messages[index]
        let next = index + 1 < messages.count ? messages[index + 1].authorId : nil
        return ChatContentFormat.showsAuthorAvatar(
            outgoing: viewModel.isOutgoing(message),
            authorId: message.authorId,
            nextAuthorId: next
        )
    }

    private func replyTitle(_ message: Message) -> String {
        if viewModel.isOutgoing(message) { return "Вы" }
        let name = message.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Ответ" : name
    }

    private func replyBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orbitleAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(privateMode.isMasked ? "Ответ" : replyTitle(message))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orbitleAccent)
                    .lineLimit(1)
                Text(privateMode.isMasked ? PrivateModeMask.messageText(outgoing: viewModel.isOutgoing(message)) : message.replySnippet)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 9)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.orbitleAccent)
                    .frame(width: 3)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить ответ")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .orbitleGlassRounded(radius: 20)
        .transition(.orbitleBar(edge: .bottom, reduceMotion: reduceMotion))
    }
}

/// Пузырь ленты. Отделён от `ChatView`, чтобы замыкания не раздували её тело.
private struct TranscriptBubble: View {
    let message: Message
    let viewModel: ChatViewModel
    let maxWidth: CGFloat
    let allowsComments: Bool
    let showsAuthorName: Bool
    let showsAuthorAvatar: Bool
    let reservesAvatar: Bool
    let group: BubbleGroup
    let canWrite: Bool
    /// «Кто отреагировал» — в группах. В личном чате и так видно, в канале — только числа.
    let showsReactionUsers: Bool
    /// Какие сообщения открыты касанием в приватном режиме.
    let reveal: PrivateModeReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let outgoing = viewModel.isOutgoing(message)
        PrivateBubbleGate(
            isRevealed: reveal.isRevealed(message.id),
            accessibilityText: PrivateModeMask.messageText(outgoing: outgoing),
            onReveal: { withAnimation(OrbitleMotion.quick(reduceMotion: reduceMotion)) { reveal.reveal(message.id) } }
        ) {
            bubble(outgoing: outgoing)
        } masked: {
            // Заглушка: «Вы получили сообщение», время и галочки; без имени, медиа и реакций.
            MessageBubble(
                message: PrivateModeMask.message(message, outgoing: outgoing),
                isOutgoing: outgoing,
                maxWidth: maxWidth,
                highlighted: viewModel.highlightedId == message.id,
                showsAuthorAvatar: showsAuthorAvatar,
                reservesAvatar: reservesAvatar,
                group: group
            )
        }
    }

    private func bubble(outgoing: Bool) -> some View {
        let reacts = viewModel.canReact(message)
        let voiceId = message.content.voices.first?.id
        return MessageBubble(
            message: message,
            isOutgoing: outgoing,
            maxWidth: maxWidth,
            phase: voiceId.map { viewModel.voicePhase(for: $0) } ?? .idle,
            allowsComments: allowsComments,
            highlighted: viewModel.highlightedId == message.id,
            showsAuthorName: showsAuthorName,
            showsAuthorAvatar: showsAuthorAvatar,
            reservesAvatar: reservesAvatar,
            group: group,
            loadingId: viewModel.loadingMediaId,
            commentCount: viewModel.commentCount(for: message),
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
            onEdit: viewModel.canEdit(message) ? { viewModel.beginEdit(message) } : nil,
            allowsReply: canWrite,
            allowsReactions: reacts,
            quickReactions: viewModel.quickReactions(for: message),
            onMoreReactions: reacts ? { viewModel.showMoreReactions(message) } : nil,
            onReactionUsers: reacts && showsReactionUsers ? { viewModel.showReactionUsers(message) } : nil,
            uploadProgress: viewModel.uploadFraction(of: message),
            onCancelUpload: { Task { await viewModel.cancelUpload(message) } },
            roundPlayer: roundPlayer
        )
    }

    /// Плеер, если в этом сообщении играет кружок.
    private var roundPlayer: AnyView? {
        guard let playback = viewModel.roundPlayback,
              message.content.visuals.contains(where: { $0.id == playback.id }) else { return nil }
        let id = playback.id
        return AnyView(
            RoundVideoPlayer(url: playback.url) { viewModel.stopRound(id: id) }
                .id(playback)
        )
    }
}

private struct TranscriptBottomPreference: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
