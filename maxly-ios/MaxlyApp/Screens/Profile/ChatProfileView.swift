import SwiftUI
import UIKit
import AVFoundation
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Звук на срок и папки из профиля: меняются через список чатов, как из меню строки.
struct ChatProfileListActions {
    var muteFor: (ChatListMenu.MuteFor) -> Void
    /// Папки для «Добавить в папку»; `nil` — менять их нечем.
    var folders: () -> [ChatListMenu.FolderChoice]?
    var toggleFolder: (String) -> Void
    var createFolder: (String) -> Void
}

/// Чат, из которого открыт профиль: его медиа, звук и переход к сообщению.
struct ChatProfileContext {
    var chat: ChatViewModel
    var isMuted: Bool
    /// Звук прямо из списка чатов: профиль обновляется сразу после переключения.
    var mutedNow: (() -> Bool)? = nil
    var onToggleMute: (() -> Void)?
    /// Вернуться в чат и подсветить сообщение.
    var onShowMessage: (Message) -> Void
    /// То же по id: из просмотра фото и видео, открытого из общих медиа.
    var onShowMessageId: ((String) -> Void)? = nil
    /// Очистить переписку или удалить чат. `true` в первом аргументе — очистка, во втором — у всех.
    var onEraseChat: ((Bool, Bool) -> Void)? = nil
    /// Выйти из группы или отписаться от канала. `nil` — не участник или это не группа и не канал.
    var onLeave: (() -> Void)? = nil
    /// «Подписаться» или «Вступить» у канала или группы вне списка (открыты из поиска).
    var join: (label: String, run: () -> Void)? = nil
    /// Открыть другой чат (общий чат собеседника).
    var onOpenChat: ((String) -> Void)? = nil
    /// Личный чат с человеком (участник группы), даже если диалога ещё нет в списке.
    var onOpenDialog: ((DialogDraft) -> Void)? = nil
    /// Поиск по чату. Профиль закрывается, поиск открывается на экране чата.
    var onSearch: (() -> Void)? = nil
    /// Опрос и отложенная отправка. `nil` — в этот чат писать нельзя.
    var onPoll: (() -> Void)? = nil
    var onSchedule: (() -> Void)? = nil
    /// Звонок собеседнику личного чата, `true` — видео. `nil` — звонить некому.
    var onCall: ((Bool) -> Void)? = nil
    /// Звук на срок и папки. `nil` — чата нет в списке.
    var list: ChatProfileListActions? = nil
    /// Куда можно отправить карточку контакта.
    var shareTargets: () -> [ChatListItem] = { [] }

    var muted: Bool { mutedNow?() ?? isMuted }
}

/// Профиль собеседника, бота, группы или канала: крупный аватар и имя,
/// ряд кнопок, карточка сведений, команды бота и общие медиа по вкладкам.
///
/// Шапка видна сразу по данным из списка чатов, остальное подгружается с сервера. Когда имя
/// уезжает под панель навигации, оно появляется в ней заголовком.
struct ChatProfileView: View {
    @Bindable var viewModel: ChatProfileViewModel
    /// Открыть переписку. `nil`, когда профиль открыт из самого чата: туда ведёт «назад».
    var onWrite: (() -> Void)?
    var chatAdmin: (any ChatAdminRepository)? = nil
    var contactList: (() -> AsyncStream<[Contact]>)? = nil
    var context: ChatProfileContext?
    var live = ChatHeaderLive()

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.imageURLSizing) private var imageURLSizing
    /// Истории собеседника: кольцо на аватаре, касание открывает их.
    @Environment(StoriesViewModel.self) private var stories: StoriesViewModel?
    @State private var copied: String?
    /// Открытый экран «Участники».
    @State private var membersList: ChatMembersListModel?
    /// Сдвиг шапки: больше нуля — профиль тянут вниз, меньше — прокрутили.
    @State private var offset: CGFloat = 0
    /// Открытый просмотр фото профиля.
    @State private var photoGallery: ProfilePhotoGallery?
    /// Где стоит аватар шапки: просмотр фото вылетает из него и возвращается в него.
    @State private var avatarFrame: CGRect = .zero
    @State private var photoSaver = ProfilePhotoSaver()
    /// Подтверждение очистки или удаления.
    @State private var erase: EraseAsk?
    /// Подтверждение выхода из группы или отписки от канала.
    @State private var leaving = false
    /// Подтверждение блокировки собеседника.
    @State private var blocking = false
    /// Лист причин жалобы.
    @State private var reporting = false
    @State private var managing = false
    /// Своя роль в группе или канале: владельцу — «Удалить канал».
    @State private var role = ChatOwnRole(isOwner: false, isAdmin: false)
    @State private var creatingFolder = false
    @State private var sharingContact = false
    /// «Своё фото…» из «Ещё» → «Обои»: выбор фото для этого чата.
    @State private var pickingWallpaper = false
    @Environment(ChatWallpaperLibrary.self) private var wallpapers: ChatWallpaperLibrary?
    @Environment(\.dismiss) private var dismiss
    @State private var manageModel: ChatManageModel?
    @State private var manageContacts: [ChatAdminPerson] = []
    /// Лист «Изменить контакт».
    @State private var editingContact = false
    /// Подтверждение «Удалить из контактов».
    @State private var removingContact = false
    @Namespace private var tabs

    private static let avatarSize: CGFloat = 100
    private static let space = "profile"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                actions
                content
                membersSection
                commonChatsSection
                sharedMedia
                contactSection
            }
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: Self.space)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                compactTitle
                    .opacity(titleShown ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: titleShown)
            }
            // «Изменить» контакт: своё имя человека в аккаунте.
            if viewModel.contactAction == .manage {
                ToolbarItem(placement: .primaryAction) {
                    Button("Изменить") { editingContact = true }
                        .disabled(viewModel.isChangingContact)
                }
            }
            // «Изменить» группу или канал, как в Max: карандаш у админа и владельца.
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button { openManage() } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Изменить")
                }
            }
        }
        .confirmationDialog(
            erase == .clear ? "Стереть переписку?" : "Удалить чат?",
            isPresented: eraseShown,
            titleVisibility: .visible
        ) {
            if let erase {
                let saved = viewModel.shown.kind == .saved
                let personal = viewModel.shown.kind == .user || viewModel.shown.kind == .bot
                if !saved {
                    Button(erase == .clear
                           ? (personal ? "Очистить у меня и у собеседника" : "Очистить у всех")
                           : (personal ? "Удалить у меня и у собеседника" : "Удалить у всех"),
                           role: .destructive) {
                        context?.onEraseChat?(erase == .clear, true)
                    }
                }
                Button(erase == .clear ? (saved ? "Очистить" : "Очистить только у меня") : (saved ? "Удалить" : "Удалить только у меня"), role: .destructive) {
                    context?.onEraseChat?(erase == .clear, false)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(erase == .clear
                 ? "Все сообщения в этом чате будут удалены без возможности восстановления."
                 : "Чат будет удалён вместе со всей перепиской.")
        }
        .sheet(isPresented: $editingContact) {
            ContactEditSheet(
                fields: viewModel.contactEditFields,
                placeholder: viewModel.contactNamePlaceholder,
                phone: viewModel.shown.phone
            ) { first, last in
                let saved = await viewModel.renameContact(firstName: first, lastName: last)
                defer { if !saved { viewModel.dismissContactError() } }
                return saved ? nil : (viewModel.contactError ?? "Не удалось сохранить имя")
            }
        }
        .confirmationDialog(ContactRemoveTexts.title(viewModel.title), isPresented: $removingContact, titleVisibility: .visible) {
            Button(ContactRemoveTexts.confirm, role: .destructive) {
                Task { _ = await viewModel.removeContact() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(ContactRemoveTexts.message)
        }
        .alert(
            "Не получилось",
            isPresented: Binding(
                get: { viewModel.contactError != nil && !editingContact },
                set: { if !$0 { viewModel.dismissContactError() } }
            )
        ) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(viewModel.contactError ?? "")
        }
        .confirmationDialog(leaveTitle, isPresented: $leaving, titleVisibility: .visible) {
            Button(isChannel ? "Отписаться" : "Покинуть группу", role: .destructive) {
                context?.onLeave?()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(isChannel
                 ? "Канал пропадёт из списка чатов. Подписаться снова можно через поиск."
                 : "Группа пропадёт из списка чатов. Вернуться можно по ссылке-приглашению.")
        }
        .confirmationDialog("Заблокировать \(viewModel.title)?", isPresented: $blocking, titleVisibility: .visible) {
            Button("Заблокировать", role: .destructive) { Task { await viewModel.toggleBlocked() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Пользователь не сможет писать вам и звонить. Разблокировать можно здесь же или в «Конфиденциальности».")
        }
        .confirmationDialog("Причина жалобы", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(viewModel.complaintReasons) { reason in
                Button(reason.title) { Task { await viewModel.complain(reasonId: reason.id) } }
            }
            Button("Отмена", role: .cancel) {}
        }
        .createFolderAlert(for: Binding(
            get: { creatingFolder ? viewModel.chatId : nil },
            set: { creatingFolder = $0 != nil }
        )) { _, title in
            context?.list?.createFolder(title)
        }
        .chatWallpaperPhotoFlow(isPresented: $pickingWallpaper, chatKey: wallpaperChatKey, library: wallpapers)
        .sheet(isPresented: $sharingContact) {
            ForwardPickerView(
                targets: context?.shareTargets() ?? [],
                onPick: { target in
                    sharingContact = false
                    guard let peer = viewModel.shown.peerId, let chat = context?.chat else { return }
                    let name = viewModel.title
                    Task { await chat.shareContact(userId: peer, name: name, to: target) }
                },
                onCancel: { sharingContact = false },
                heading: "Поделиться контактом"
            )
        }
        .task(id: viewModel.shown.kind) {
            guard let chat = context?.chat, viewModel.shown.kind == .group || viewModel.shown.kind == .channel else { return }
            role = await chat.ownRole()
        }
        .sheet(item: $membersList) { model in
            ChatMembersView(
                model: model,
                onOpenDialog: memberDialogOpener,
                onClose: { membersList = nil }
            )
        }
        .sheet(isPresented: $managing) {
            if let manageModel {
                ChatManageView(model: manageModel, contacts: manageContacts)
            }
        }
        .task { await viewModel.watchPresence() }
        .task {
            await viewModel.loadIfStale()
            await viewModel.loadExtras()
            // Кольцо владельца вне ленты профиль спрашивает сам (один раз за сеанс).
            await stories?.loadRing(storyOwner, kind: storyKind)
        }
        .refreshable { await viewModel.load() }
        .task(id: sharedVersion) {
            guard let chat = context?.chat else { return }
            await viewModel.updateShared(chat.messages, currentUserId: chat.currentUserId) {
                await chat.sharedHistory()
            }
        }
        .task(id: hasSharedAnchor) {
            // Все общие медиа с сервера, а не только загруженная в чате история. Ключ меняется
            // один раз — когда у чата появляется серверное сообщение; новое сообщение обход не сбивает.
            guard let chat = context?.chat, hasSharedAnchor else { return }
            await viewModel.loadRemoteShared(window: chat.messages) { await chat.sharedMedia($0) }
        }
        .overlay(alignment: .bottom) { toast }
        .animation(.snappy, value: copied)
        .animation(.snappy, value: viewModel.actionNotice)
        .animation(.snappy, value: context?.chat.notice)
        .modifier(ProfileChatCovers(chat: context?.chat, onShowMessage: context?.onShowMessageId))
        .mediaViewerCover(item: $photoGallery) { gallery in
            ProfilePhotoViewer(gallery: gallery, title: viewModel.title, saver: photoSaver) { photoGallery = nil }
        }
    }

    /// Шапка ушла под панель навигации — имя и статус видны в ней.
    private var titleShown: Bool { offset < -(Self.avatarSize + 24) }

    private var hasSharedAnchor: Bool {
        context.map { SharedMediaPager.anchor(in: $0.chat.messages) != nil } ?? false
    }

    private var sharedVersion: Int {
        guard let chat = context?.chat else { return 0 }
        return chat.transcriptVersion &* 31 &+ chat.contentVersion
    }

    // MARK: Шапка

    private var header: some View {
        VStack(spacing: 6) {
            avatar
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                Text(viewModel.title)
                    .font(.app(size: 24, .semibold))
                    .multilineTextAlignment(.center)
                if viewModel.isOfficial || live.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.maxlyAccent)
                        .accessibilityLabel("Официальный")
                }
                if context?.muted == true {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Без звука")
                }
            }
            status(font: .app(size: 15))
        }
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { offset = proxy.frame(in: .named(Self.space)).minY }
                    .onChange(of: proxy.frame(in: .named(Self.space)).minY) { _, value in offset = value }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Аватар растёт, когда профиль тянут вниз, и уменьшается и тает при прокрутке.
    private var avatar: some View {
        let pull = max(offset, 0)
        let scroll = min(offset, 0)
        let scale = reduceMotion ? 1 : (pull > 0 ? 1 + min(pull, 160) / 320 : max(0.55, 1 + scroll / 220))
        let owner = storyOwner
        let hasStories = stories?.ring(of: owner, kind: storyKind) != nil
        let canOpen = viewModel.shown.fullPhotoURL != nil
        // С кольцом историй касание открывает истории, долгое нажатие — фото.
        let tap: () -> Void = {
            if hasStories, let owner {
                _ = stories?.open(owner, kind: storyKind)
            } else {
                openPhoto(inRing: false)
            }
        }
        return ChatHeaderAvatar(viewModel: viewModel, size: Self.avatarSize, isOnline: viewModel.isOnline || live.isOnline)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
            .opacity(MediaSourceRegistry.shared.hiddenId == photoTileId ? 0 : 1)
            .onDisappear { MediaSourceRegistry.shared.remove(photoTileId) }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.4) {
                if hasStories && canOpen { openPhoto(inRing: true) }
            }
            .allowsHitTesting(canOpen || hasStories)
            .scaleEffect(scale, anchor: pull > 0 ? .top : .bottom)
            .opacity(reduceMotion ? 1 : Double(max(0, min(1, 1 + (scroll + 40) / 80))))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hasStories ? "Открывает истории" : "")
            .accessibilityAction(.default, tap)
            .accessibilityActions {
                if hasStories && canOpen {
                    Button("Открыть фото") { openPhoto(inRing: true) }
                }
            }
        .accessibilityLabel("Фото профиля")
    }

    private var photoTileId: String { "profile-photo-\(viewModel.chatId)" }

    /// Фото на весь экран: сразу видна маленькая картинка из кэша (с ней же кадр вылетает из
    /// аватара), потом её сменяет оригинал — снимок целиком, если ядро его дало.
    /// `inRing` — фото внутри кольца историй: оно меньше аватара (как в `StoryRingAvatar`).
    private func openPhoto(inRing: Bool) {
        guard let full = viewModel.shown.fullPhotoURL else { return }
        // Подписанный адрес истёк: карточка перечитывается, новые адреса — у неё.
        if imageURLSizing.isExpired(full.absoluteString, nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) {
            Task {
                await viewModel.load()
                showPhoto(inRing: inRing)
            }
            return
        }
        showPhoto(inRing: inRing)
    }

    private func showPhoto(inRing: Bool) {
        let id = photoTileId
        guard let gallery = viewModel.photoGallery(tileId: id) else { return }
        let size = Self.avatarSize
        let photoSize = inRing ? size - min(max(size * 0.045, 2), 3.5) * 4 : size
        // Тот же адрес и размер декодирования, что у аватара шапки (`ChatAvatarView`):
        // картинка берётся из кэша без новой загрузки.
        let small = ImageURLRequests.url(
            viewModel.shown.avatarURL, shape: .square, pointSize: photoSize, scale: displayScale,
            fullScreen: false, sizing: imageURLSizing
        )
        if avatarFrame.width > 0 {
            let frame = avatarFrame.insetBy(dx: (size - photoSize) / 2, dy: (size - photoSize) / 2)
            MediaSourceRegistry.shared.update(id, .init(frame: frame, url: small, maxPixel: Int(photoSize * 3), cornerRadius: frame.width / 2))
        }
        photoGallery = gallery
    }

    /// Владелец колец: человек, бот, группа или канал.
    private var storyOwner: String? {
        switch viewModel.shown.kind {
        case .user, .bot: viewModel.shown.peerId
        case .group, .channel: viewModel.chatId
        case .saved: nil
        }
    }

    private var storyKind: StoryOwner.Kind {
        switch viewModel.shown.kind {
        case .group: .chat
        case .channel: .channel
        default: .user
        }
    }

    private var compactTitle: some View {
        VStack(spacing: 1) {
            Text(viewModel.title)
                .font(.app(size: 17, .semibold))
                .lineLimit(1)
            status(font: .app(size: 13))
        }
    }

    /// Статус пересчитывается раз в минуту: «был(а) N минут назад» не застывает.
    private func status(font: Font) -> some View {
        TimelineView(.everyMinute) { context in
            statusLine(viewModel.headerStatus(live, at: context.date), font: font)
        }
    }

    @ViewBuilder
    private func statusLine(_ status: ChatHeaderStatus, font: Font) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .plain(let text):
            Text(text).font(font).foregroundStyle(.secondary).lineLimit(1)
        case .accent(let text):
            Text(text).font(font).foregroundStyle(Color.maxlyAccent).lineLimit(1)
        case .typing(let text):
            TypingStatus(text: text, font: font)
        }
    }

    // MARK: Кнопки

    /// Плитки и «Ещё» как в Max (`ProfileMenu`). Профиль участника (без чата) — «Чат» и «Ещё».
    @ViewBuilder
    private var actions: some View {
        let tiles = profileTiles
        if tiles.count > 1 || !profileEntries.isEmpty {
            HStack(spacing: 8) {
                ForEach(tiles, id: \.self) { tile in
                    tileView(tile)
                }
            }
            .padding(.horizontal, MaxlyTheme.pad)
        }
    }

    /// Чат в списке: иначе группа или канал открыты из поиска и есть «Вступить».
    private var listed: Bool { context?.join == nil }

    private var profileTiles: [ProfileMenu.Tile] {
        let kind = viewModel.shown.kind
        let tiles = ProfileMenu.tiles(
            kind: kind,
            listed: listed,
            calls: context?.onCall != nil,
            sound: kind != .saved && context?.onToggleMute != nil
        )
        return tiles.filter { tile in
            switch tile {
            case .chat: (viewModel.canWrite && onWrite != nil) || context != nil
            case .search: context?.onSearch != nil
            case .join, .subscribe: context?.join != nil
            case .more: !profileEntries.isEmpty
            default: true
            }
        }
    }

    private var profileEntries: [ProfileMenu.Entry] {
        let kind = viewModel.shown.kind
        let ring = stories?.ring(of: storyOwner, kind: storyKind)
        let ownRing = ring != nil && ring?.owner == stories?.own?.owner
        let tiles = ProfileMenu.tiles(kind: kind, listed: listed, calls: context?.onCall != nil, sound: context?.onToggleMute != nil)
            .filter { $0 != .search || context?.onSearch != nil }
        return ProfileMenu.entries(
            kind: kind,
            tiles: tiles,
            listed: listed,
            hasLink: viewModel.shareURL != nil,
            folders: context?.list?.folders(),
            hasStories: ring != nil && !ownRing,
            canReport: viewModel.complaintTarget != nil,
            isAdmin: role.isAdmin,
            isOwner: role.isOwner,
            blocked: viewModel.canBlock ? viewModel.isBlocked : nil,
            canErase: context?.onEraseChat != nil
        ).filter { entry in
            switch entry {
            case .shareContact: context != nil && viewModel.shown.peerId != nil
            case .search: context?.onSearch != nil
            case .leave: context?.onLeave != nil
            default: true
            }
        }
    }

    @ViewBuilder
    private func tileView(_ tile: ProfileMenu.Tile) -> some View {
        switch tile {
        case .sound:
            soundTile
        case .more:
            moreTile
        default:
            Button { run(tile) } label: {
                ActionTile(title: tileTitle(tile), systemImage: tileIcon(tile))
            }
            .buttonStyle(ActionTileStyle())
        }
    }

    private func tileTitle(_ tile: ProfileMenu.Tile) -> String {
        switch tile {
        case .join, .subscribe: context?.join?.label ?? tile.title
        default: tile.title
        }
    }

    private func tileIcon(_ tile: ProfileMenu.Tile) -> String {
        switch tile {
        case .chat: "bubble.left.fill"
        case .call: "phone.fill"
        case .video: "video.fill"
        case .sound: "bell.fill"
        case .search: "magnifyingglass"
        case .join, .subscribe: "plus.circle.fill"
        case .more: "ellipsis"
        }
    }

    private func run(_ tile: ProfileMenu.Tile) {
        switch tile {
        case .chat: if let onWrite, viewModel.canWrite { onWrite() } else { dismiss() }
        case .call: context?.onCall?(false)
        case .video: context?.onCall?(true)
        case .search: context?.onSearch?()
        case .join, .subscribe: context?.join?.run()
        case .sound, .more: break
        }
    }

    /// «Звук»: выключенный включается касанием, включённый выключается на срок.
    @ViewBuilder
    private var soundTile: some View {
        let muted = context?.muted == true
        if muted || context?.list == nil {
            Button { context?.onToggleMute?() } label: {
                ActionTile(title: "Звук", systemImage: muted ? "bell.slash.fill" : "bell.fill")
            }
            .buttonStyle(ActionTileStyle())
        } else {
            Menu {
                ForEach(ChatListMenu.MuteFor.allCases, id: \.self) { choice in
                    Button(role: choice.isDanger ? .destructive : nil) {
                        context?.list?.muteFor(choice)
                    } label: {
                        Text(choice.title)
                    }
                }
            } label: {
                ActionTile(title: "Звук", systemImage: "bell.fill")
            }
            .buttonStyle(ActionTileStyle())
        }
    }

    private var moreTile: some View {
        Menu {
            ForEach(profileEntries, id: \.self) { entry in
                entryView(entry)
            }
            extras
        } label: {
            ActionTile(title: "Ещё", systemImage: "ellipsis")
        }
        .buttonStyle(ActionTileStyle())
    }

    @ViewBuilder
    private func entryView(_ entry: ProfileMenu.Entry) -> some View {
        switch entry {
        case .shareContact:
            Button { sharingContact = true } label: { Label(entry.title, systemImage: "square.and.arrow.up") }
        case .shareLink:
            if let url = viewModel.shareURL {
                ShareLink(item: url) { Label(entry.title, systemImage: "link") }
            }
        case .folders(let folders):
            FolderMenu(
                folders: folders,
                onToggle: { context?.list?.toggleFolder($0) },
                onCreate: { creatingFolder = true }
            )
        case .search:
            Button { context?.onSearch?() } label: { Label(entry.title, systemImage: "magnifyingglass") }
        case .erase:
            Button { erase = .clear } label: { Label(entry.title, systemImage: "eraser") }
        case .hideStories:
            Button {
                guard let owner = storyOwner else { return }
                Task { await stories?.hideOwner(StoryOwner(id: owner, kind: storyKind), name: viewModel.title) }
            } label: {
                Label(entry.title, systemImage: "eye.slash")
            }
        case .report:
            Button {
                Task { if await viewModel.loadComplaintReasons() { reporting = true } }
            } label: {
                Label(entry.title, systemImage: "exclamationmark.bubble")
            }
        case .block(let blocked):
            Button(role: blocked ? nil : .destructive) {
                if blocked { Task { await viewModel.toggleBlocked() } } else { blocking = true }
            } label: {
                Label(entry.title, systemImage: blocked ? "lock.open" : "hand.raised")
            }
        case .leave:
            Button(role: .destructive) { leaving = true } label: {
                Label(entry.title, systemImage: "rectangle.portrait.and.arrow.right")
            }
        case .delete:
            Button(role: .destructive) { erase = .delete } label: {
                Label(entry.title, systemImage: "trash")
            }
        }
    }

    /// Группа или канал, где аккаунт админ или владелец: в панели навигации есть «Изменить».
    private var canEdit: Bool {
        (viewModel.shown.kind == .group || viewModel.shown.kind == .channel) && chatAdmin != nil && listed && role.isAdmin
    }

    /// Ключ обоев чата («Ещё» → «Обои»): только профиль, открытый из самого чата.
    private var wallpaperChatKey: String? {
        guard wallpapers != nil, let chat = context?.chat else { return nil }
        return ChatWallpaperLibrary.chatKey(account: chat.currentUserId, chatId: chat.chatId)
    }

    /// Чего нет в меню Max, но есть у нас: опрос, отложенная отправка и свои обои чата.
    @ViewBuilder
    private var extras: some View {
        if context?.onPoll != nil || context?.onSchedule != nil || wallpaperChatKey != nil {
            Section {
                if let poll = context?.onPoll {
                    Button(action: poll) { Label("Опрос", systemImage: "chart.bar") }
                }
                if let schedule = context?.onSchedule {
                    Button(action: schedule) { Label("Отправить позже", systemImage: "clock") }
                }
                if let wallpapers, let key = wallpaperChatKey {
                    ChatWallpaperMenu(chatKey: key, library: wallpapers) { pickingWallpaper = true }
                }
            }
        }
    }

    private enum EraseAsk: Equatable { case clear, delete }

    private func openManage() {
        guard let chatAdmin else { return }
        manageModel = ChatManageModel(
            chatId: viewModel.chatId,
            isChannel: viewModel.shown.kind == .channel,
            title: viewModel.title,
            about: viewModel.shown.description ?? "",
            repository: chatAdmin
        )
        managing = true
        guard let contactList else { return }
        Task {
            for await list in contactList() {
                manageContacts = list.map { ChatAdminPerson(id: $0.id, name: $0.displayName) }
                break
            }
        }
    }

    private var isChannel: Bool { viewModel.shown.kind == .channel }

    private var leaveTitle: String {
        isChannel ? "Отписаться от канала?" : "Покинуть группу?"
    }

    private var eraseShown: Binding<Bool> {
        Binding(get: { erase != nil }, set: { if !$0 { erase = nil } })
    }

    // MARK: Сведения

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
        case .failed(let message):
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Повторить") { Task { await viewModel.load() } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        case .loaded:
            let rows = viewModel.infoRows
            if !rows.isEmpty {
                card {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().padding(.leading, 16) }
                        infoRow(row)
                    }
                }
            }
            let commands = viewModel.commands
            if !commands.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("КОМАНДЫ")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, MaxlyTheme.pad + 16)
                    card {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            if index > 0 { Divider().padding(.leading, 16) }
                            commandRow(command)
                        }
                    }
                }
            }
        }
    }

    // MARK: Участники и общие чаты

    /// Касание участника: экран «Участники» закрывается, открывается личный чат.
    private var memberDialogOpener: ((DialogDraft) -> Void)? {
        guard let open = context?.onOpenDialog else { return nil }
        return { draft in
            membersList = nil
            open(draft)
        }
    }

    /// Участники группы: первые 50 с аватарами.
    @ViewBuilder
    private var membersSection: some View {
        let members = viewModel.members
        if !members.isEmpty {
            section(title: "УЧАСТНИКИ") {
                if let chat = context?.chat, viewModel.membersList(currentUserId: chat.currentUserId) != nil {
                    Button {
                        membersList = viewModel.membersList(currentUserId: chat.currentUserId)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2")
                                .frame(width: 36, height: 36)
                                .foregroundStyle(Color.maxlyAccent)
                            Text("Все участники и поиск")
                                .font(.app(.body))
                                .foregroundStyle(Color.maxlyAccent)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.app(.footnote, .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 64)
                }
                ForEach(Array(members.prefix(50).enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider().padding(.leading, 64) }
                    HStack(spacing: 12) {
                        AvatarView(title: member.name, id: member.id, url: member.avatarURL, size: 36)
                        Text(member.name)
                            .font(.app(.body))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Общие чаты с собеседником. Нажатие открывает чат.
    @ViewBuilder
    private var commonChatsSection: some View {
        let chats = viewModel.commonChats
        if !chats.isEmpty {
            section(title: "ОБЩИЕ ЧАТЫ") {
                ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                    if index > 0 { Divider().padding(.leading, 64) }
                    Button {
                        context?.onOpenChat?(chat.id)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(title: chat.title, id: chat.id, url: chat.avatarURL, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(chat.title)
                                    .font(.app(.body))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if chat.participants > 0 {
                                    Text(ChatProfileViewModel.membersText(chat.participants, channel: chat.isChannel))
                                        .font(.app(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowStyle())
                    .disabled(context?.onOpenChat == nil)
                }
            }
        }
    }

    /// Отдельный блок внизу: «Удалить из контактов» у контакта, «Добавить в контакты» у остальных людей.
    @ViewBuilder
    private var contactSection: some View {
        switch viewModel.contactAction {
        case .manage:
            card {
                Button(role: .destructive) { removingContact = true } label: {
                    contactRow(ContactRemoveTexts.menuItem, systemImage: "person.crop.circle.badge.minus", tint: .red)
                }
                .buttonStyle(RowStyle())
                .disabled(viewModel.isChangingContact)
            }
        case .add:
            card {
                Button { Task { _ = await viewModel.addToContacts() } } label: {
                    contactRow("Добавить в контакты", systemImage: "person.crop.circle.badge.plus", tint: .maxlyAccent)
                }
                .buttonStyle(RowStyle())
                .disabled(viewModel.isChangingContact)
            }
        case .none:
            EmptyView()
        }
    }

    private func contactRow(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.app(.body))
                .frame(width: 24)
            Text(title)
                .font(.app(.body))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func section<Rows: View>(title: String, @ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .padding(.horizontal, MaxlyTheme.pad + 16)
            card(rows)
        }
    }

    private func card<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        VStack(spacing: 0, content: rows)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .padding(.horizontal, MaxlyTheme.pad)
    }

    private func infoRow(_ row: ChatProfileViewModel.InfoRow) -> some View {
        Button {
            perform(row)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                Text(row.value)
                    .font(.app(.body))
                    .foregroundStyle(isLink(row) ? AnyShapeStyle(Color.maxlyAccent) : AnyShapeStyle(.primary))
                    .underline(row.action.map { if case .open = $0 { true } else { false } } ?? false)
                    .lineLimit(row.isMultiline ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: row.isMultiline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .contextMenu {
            Button("Скопировать", systemImage: "doc.on.doc") {
                copy(row.value, message: "Скопировано")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func commandRow(_ command: ChatProfileViewModel.CommandRow) -> some View {
        Button {
            copy(command.command, message: "Команда скопирована")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.command)
                    .font(.appMono(.body))
                    .foregroundStyle(Color.maxlyAccent)
                if let description = command.description {
                    Text(description)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
    }

    private func isLink(_ row: ChatProfileViewModel.InfoRow) -> Bool {
        switch row.action {
        case .call, .open: true
        case .copy, nil: false
        }
    }

    private func perform(_ row: ChatProfileViewModel.InfoRow) {
        switch row.action {
        case .call(let url), .open(let url):
            openURL(url)
        case .copy:
            copy(row.value, message: "Скопировано")
        case nil:
            break
        }
    }

    // MARK: Общие медиа

    @ViewBuilder
    private var sharedMedia: some View {
        let shared = viewModel.shared
        if let chat = context?.chat, !shared.isEmpty {
            VStack(spacing: 0) {
                tabStrip(shared.tabs)
                Divider()
                Group {
                    switch viewModel.sharedTab {
                    case .media: mediaGrid(shared.media, chat: chat)
                    case .files: fileList(shared.files, chat: chat)
                    case .links: linkList(shared.links)
                    case .voice: voiceList(shared.voices, chat: chat)
                    }
                }
                .padding(.top, viewModel.sharedTab == .media ? 1 : 0)
                if viewModel.isLoadingRemoteShared {
                    // Сервер ещё отдаёт страницы: под сеткой видно, что будет больше.
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    /// Вкладки строкой с полоской под выбранной.
    private func tabStrip(_ list: [SharedMediaTab]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(list) { tab in
                    let selected = viewModel.sharedTab == tab
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { viewModel.sharedTab = tab }
                    } label: {
                        Text(tab.title)
                            .font(.app(size: 15, .semibold))
                            .foregroundStyle(selected ? Color.maxlyAccent : .secondary)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if selected {
                                    Capsule()
                                        .fill(Color.maxlyAccent)
                                        .frame(height: 3)
                                        .matchedGeometryEffect(id: "tab", in: tabs)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, MaxlyTheme.pad)
        }
    }

    private func mediaGrid(_ items: [SharedMedia.Visual], chat: ChatViewModel) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(items) { item in
                Button {
                    chat.presentMedia(item.message, startId: item.attachmentId)
                } label: {
                    SharedMediaCell(item: item, isLoading: chat.loadingMediaId == item.attachmentId)
                }
                .buttonStyle(.plain)
                .contextMenu { showInChat(item.message) }
            }
        }
    }

    private func fileList(_ items: [SharedMedia.File], chat: ChatViewModel) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    chat.openFile(item.message, attachmentId: item.file.id)
                } label: {
                    SharedRow {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.maxlyAccent)
                            .overlay {
                                if chat.loadingMediaId == item.file.id {
                                    ProgressView().tint(Color.maxlyOnAccent)
                                } else {
                                    Text(item.ext)
                                        .font(.app(size: 12, .bold))
                                        .foregroundStyle(Color.maxlyOnAccent)
                                }
                            }
                    } title: {
                        Text(item.file.name).lineLimit(1).truncationMode(.middle)
                    } details: {
                        Text(item.details)
                    }
                }
                .buttonStyle(RowStyle())
                .contextMenu { showInChat(item.message) }
            }
        }
    }

    private func linkList(_ items: [SharedMedia.Link]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    openURL(item.url)
                } label: {
                    SharedRow {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AvatarPalette.gradient(ChatAvatar.colorIndex(for: item.host)))
                            .overlay {
                                Text(item.letter)
                                    .font(.app(size: 20, .semibold))
                                    .foregroundStyle(.white)
                            }
                    } title: {
                        Text(item.host).lineLimit(1)
                    } details: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let context = item.context {
                                Text(context).lineLimit(2)
                            }
                            Text(item.url.absoluteString)
                                .foregroundStyle(Color.maxlyAccent)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(RowStyle())
                .contextMenu {
                    Button("Скопировать ссылку", systemImage: "doc.on.doc") {
                        copy(item.url.absoluteString, message: "Ссылка скопирована")
                    }
                    showInChat(item.message)
                }
            }
        }
    }

    private func voiceList(_ items: [SharedMedia.Voice], chat: ChatViewModel) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                let phase = chat.voicePhase(for: item.voice.id)
                Button {
                    chat.toggleVoice(item.message)
                } label: {
                    SharedRow {
                        Circle()
                            .fill(Color.maxlyAccent)
                            .overlay {
                                switch phase {
                                case .downloading:
                                    ProgressView().tint(Color.maxlyOnAccent)
                                case .playing:
                                    Image(systemName: "pause.fill").foregroundStyle(Color.maxlyOnAccent)
                                case .idle, .paused, .failed:
                                    Image(systemName: "play.fill").foregroundStyle(Color.maxlyOnAccent).offset(x: 1)
                                }
                            }
                    } title: {
                        Text(item.author).lineLimit(1)
                    } details: {
                        Text(item.details).monospacedDigit()
                    }
                }
                .buttonStyle(RowStyle())
                .contextMenu { showInChat(item.message) }
            }
        }
    }

    @ViewBuilder
    private func showInChat(_ message: Message) -> some View {
        if let context {
            Button("Показать в чате", systemImage: "bubble.left.and.text.bubble.right") {
                context.onShowMessage(message)
            }
        }
    }

    // MARK: Уведомления

    @ViewBuilder
    private var toast: some View {
        if let text = copied ?? viewModel.actionNotice ?? context?.chat.notice {
            Text(text)
                .font(.app(.footnote, .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func copy(_ text: String, message: String) {
        UIPasteboard.general.string = text
        copied = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copied == message { copied = nil }
        }
    }
}

/// Просмотр фото и видео и предпросмотр файлов, открытые из общих медиа: сам чат под
/// профилем свои окна в это время не показывает.
private struct ProfileChatCovers: ViewModifier {
    let chat: ChatViewModel?
    var onShowMessage: ((String) -> Void)?

    /// «Перейти к сообщению» из просмотра: профиль уезжает, лента едет к сообщению.
    private func showAction(_ request: MediaViewerRequest) -> (() -> Void)? {
        guard let id = request.messageId, let onShowMessage else { return nil }
        return { onShowMessage(id) }
    }

    func body(content: Content) -> some View {
        if let chat {
            @Bindable var model = chat
            content
                .mediaViewerCover(item: $model.viewer) { request in
                    MediaViewer(
                        request: request,
                        download: { await chat.downloadVideo($0, progress: $1) },
                        notice: chat.notice,
                        isSaving: chat.isSaving,
                        onSave: { chat.saveViewerSlide($0, to: $1) },
                        onShowInChat: showAction(request)
                    ) { chat.viewer = nil }
                        .fileExportSheet(chat, fromViewer: true)
                }
                .fullScreenCover(item: $model.openedFile) { file in
                    FileQuickLook(url: file.url, title: file.name) { chat.openedFile = nil }
                }
        } else {
            content
        }
    }
}

/// Аватар чата: у «Избранного» закладка, у остальных фото или буквы.
struct ChatHeaderAvatar: View {
    let viewModel: ChatProfileViewModel
    let size: CGFloat
    var isOnline = false
    var reservesRingSpace = false
    /// Собеседник с историями — аватар в кольце. Заглушки приватного режима колец не показывают.
    @Environment(StoriesViewModel.self) private var stories: StoriesViewModel?
    @Environment(\.privateMode) private var privateMode

    var body: some View {
        if viewModel.shown.kind == .saved {
            ChatAvatarView(avatar: ChatAvatar(kind: .savedMessages, colorIndex: 0), size: savedSize)
                .frame(width: size, height: size)
        } else {
            let initials = ChatAvatar.initials(for: viewModel.title)
            let kind: ChatAvatar.Kind = viewModel.shown.avatarURL.map { .photo($0, initials: initials) } ?? .initials(initials)
            let id = viewModel.shown.peerId ?? viewModel.chatId
            let ownerKind: StoryOwner.Kind = switch viewModel.shown.kind {
            case .group: .chat
            case .channel: .channel
            default: .user
            }
            let ownerId: String? = switch viewModel.shown.kind {
            case .user, .bot: viewModel.shown.peerId
            case .group, .channel: viewModel.chatId
            case .saved: nil
            }
            let ring = privateMode != .placeholder ? stories?.ring(of: ownerId, kind: ownerKind) : nil
            StoryRingAvatar(avatar: ChatAvatar(kind: kind, colorIndex: ChatAvatar.colorIndex(for: id)), ring: ring, size: size, isOnline: isOnline, reservesRingSpace: reservesRingSpace)
                .accessibilityLabel(privateMode.isMasked ? "" : viewModel.title)
        }
    }

    /// Закладка «Избранного» с местом под кольцо — того же размера, что фото внутри кольца.
    private var savedSize: CGFloat {
        guard reservesRingSpace else { return size }
        let stroke: CGFloat = min(max(size * 0.045, 2), 3.5)
        return size - stroke * 4
    }
}

/// «печатает» с тремя бегущими точками, цветом акцента.
struct TypingStatus: View {
    let text: String
    var font: Font = .app(size: 13)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .frame(width: 4, height: 4)
                            .opacity(reduceMotion ? 0.8 : Self.pulse(time, index))
                    }
                }
            }
            Text(text)
                .font(font)
                .lineLimit(1)
        }
        .foregroundStyle(Color.maxlyAccent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    /// Точки вспыхивают по очереди, цикл 1,2 с.
    private static func pulse(_ time: TimeInterval, _ index: Int) -> Double {
        let phase = (time / 1.2 - Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        return 0.3 + 0.7 * max(0, sin(phase * .pi))
    }
}

/// Плитка ряда кнопок профиля: значок над подписью на карточке.
private struct ActionTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
            Text(title)
                .font(.app(size: 12, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.maxlyAccent)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ActionTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Строка карточки: подсветка при нажатии на всю ширину.
private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(uiColor: .systemFill) : .clear)
    }
}

/// Строка списка общих медиа: значок 42 pt, название, подробности, разделитель под текстом.
private struct SharedRow<Icon: View, Title: View, Details: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let title: Title
    @ViewBuilder let details: Details

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                details
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            // Своя линия: `Divider` в overlay строки HStack становился вертикальным.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1 / 3)
            }
        }
        .padding(.leading, MaxlyTheme.pad)
        .contentShape(Rectangle())
    }
}

/// Квадрат сетки медиа: превью, у видео длительность в углу.
private struct SharedMediaCell: View {
    let item: SharedMedia.Visual
    let isLoading: Bool

    var body: some View {
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if item.thumbnailURL == nil, let file = item.videoFile {
                    VideoFrame(file: file)
                } else {
                    RemoteImage(url: item.thumbnailURL, maxPixel: 360) {
                        if let data = item.preview, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                    .scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let duration = item.duration {
                    Text(duration)
                        .font(.app(size: 12, .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(4)
                }
            }
            .overlay {
                if isLoading { ProgressView().tint(.white) }
            }
            // Просмотр вылетает из клетки и возвращается в неё, как из плитки в ленте.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MediaSourceRegistry.shared.update(item.attachmentId, .init(frame: frame, url: item.thumbnailURL, maxPixel: 360, cornerRadius: 0))
            }
            .onDisappear { MediaSourceRegistry.shared.remove(item.attachmentId) }
            .opacity(MediaSourceRegistry.shared.hiddenId == item.attachmentId ? 0 : 1)
            .contentShape(Rectangle())
            .accessibilityLabel(item.duration == nil ? "Фото" : "Видео, \(item.duration ?? "")")
    }
}

/// Первый кадр своего ролика без обложки (вне главного потока).
private struct VideoFrame: View {
    let file: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: file) {
            if let frame = await Self.frame(file) { image = UIImage(cgImage: frame) }
        }
    }

    /// Генератор живёт внутри одного вызова и не пересекает границы акторов.
    private nonisolated static func frame(_ file: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        return try? await generator.image(at: .zero).image
    }
}

/// Профиль, модель которого создаётся один раз при переходе, а не при каждой перерисовке
/// экрана, откуда перешли: иначе загруженная карточка терялась бы.
struct ProfileDestination: View {
    let make: () -> ChatProfileViewModel?
    var onWrite: (() -> Void)?
    @State private var model: ChatProfileViewModel?

    var body: some View {
        Group {
            if let model {
                ChatProfileView(viewModel: model, onWrite: onWrite)
            } else {
                ProgressView()
            }
        }
        // Профиль открывают осознанно, и приватный режим его не прячет.
        .environment(\.privateMode, .visible)
        .onAppear {
            if model == nil { model = make() }
        }
    }
}
