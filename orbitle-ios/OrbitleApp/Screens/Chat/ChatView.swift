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
    /// Сеть, «печатает…», звук и галочка — живые данные из списка чатов для шапки.
    var live: () -> ChatHeaderLive = { ChatHeaderLive() }
    /// Модель профиля чата: шапка берёт из неё статус, нажатие на шапку открывает профиль.
    var makeProfile: (() -> ChatProfileViewModel?)?
    @State private var profile: ChatProfileViewModel?
    @State private var profileShown = false
    @State private var forwardList: [ChatListItem] = []
    @State private var attachmentsShown = false
    @State private var recording = RecordingSession()
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Приватный режим: пузыри закрыты заглушкой или размытием, касание открывает на время.
    @Environment(\.privateMode) private var privateMode
    @Environment(PrivateModeSettings.self) private var privateModeSettings: PrivateModeSettings?
    @State private var reveal = PrivateModeReveal()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ChatTranscript(
            viewModel: viewModel,
            chatType: chatType,
            commentsEnabled: commentsEnabled,
            canWrite: canWrite,
            reveal: reveal,
            focus: $composerFocused
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            if privateMode.isMasked { privateModeBanner }
        }
        // Режим включают и выключают и с другого экрана: капсула всё равно выезжает плавно.
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: privateMode)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposer(
                viewModel: viewModel,
                recording: recording,
                focus: $composerFocused,
                attachmentsShown: $attachmentsShown,
                canWrite: canWrite,
                chatType: chatType,
                isMuted: isMuted,
                onToggleMute: onToggleMute
            )
        }
        // Видимость tab bar управляется стабильным MainTabView.
        // Системный заголовок (и подпись кнопки «назад» следующего экрана) размыть нельзя:
        // в приватном режиме там всегда общее «Личный чат» / «Групповой чат».
        .navigationTitle(shownTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: openProfile) {
                    ChatHeaderTitle(
                        title: title,
                        maskedTitle: maskedTitle,
                        status: privateMode.isMasked ? .none : headerStatus,
                        isVerified: live().isVerified || profile?.isOfficial == true,
                        isMuted: isMuted
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(shownTitle), открыть профиль")
            }
            if let profile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openProfile) {
                        ChatHeaderAvatar(viewModel: profile, size: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Профиль")
                }
            }
        }
        .navigationDestination(isPresented: $profileShown) {
            if let profile {
                ChatProfileView(
                    viewModel: profile,
                    context: ChatProfileContext(
                        chat: viewModel,
                        isMuted: isMuted,
                        onToggleMute: onToggleMute,
                        onShowMessage: { showInChat($0) }
                    ),
                    live: live()
                )
                // Профиль открывают осознанно, и приватный режим его не прячет.
                .environment(\.privateMode, .visible)
            }
        }
        .task {
            // Шапка: статус и аватар из карточки чата, она же открывается профилем.
            if profile == nil { profile = makeProfile?() }
            await profile?.load()
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
        .fullScreenCover(item: profileShown ? .constant(nil) : $viewModel.viewer) { request in
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
        .fullScreenCover(item: profileShown ? .constant(nil) : $viewModel.openedFile) { file in
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

    private var headerStatus: ChatHeaderStatus {
        profile?.headerStatus(live()) ?? .none
    }

    private func openProfile() {
        guard profile != nil else { return }
        composerFocused = false
        profileShown = true
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
        chatType == .channel && commentsEnabled != false
    }
}
