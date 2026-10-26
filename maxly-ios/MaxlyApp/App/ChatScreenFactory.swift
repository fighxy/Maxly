import Foundation
import MaxlyDomain
import MaxlyPresentation

/// Входы экрана чата из контейнера приложения и навигации: данные чата из списка, службы и
/// действия списка чатов. Раньше эта проводка — три десятка параметров — жила в `RootView`.
@MainActor
struct ChatScreenFactory {
    let container: AppContainer
    let router: AppRouter
    /// Полоса «играет голосовое»: открыть чат на этом сообщении.
    let openVoice: (VoiceNowPlaying.Track) -> Void

    func context(chatId id: String) -> ChatScreenContext {
        let container = container
        let router = router
        let settings = container.accountSettingsModel().settings
        return ChatScreenContext(
            info: ChatScreenContext.Info(
                title: container.chatTitle(id: id),
                commentsEnabled: container.commentsEnabled(id: id),
                chatType: container.chatType(id: id),
                canWrite: container.canWrite(id: id),
                isMuted: container.isMuted(id: id),
                quickReaction: settings.quickReactionEnabled ? settings.quickReaction : nil,
                opensProfile: router.profileRequest == id
            ),
            services: ChatScreenContext.Services(
                forwardTargets: { container.forwardTargets(excluding: id) },
                mutedNow: { container.isMuted(id: id) },
                contactList: { container.attachmentContacts() },
                stickerPanel: container.stickerPanelModel(),
                live: { container.headerLive(id: id) },
                makeProfile: { container.profileViewModel(chatId: id) },
                makeParticipantProfile: { container.profileViewModel(dialog: $0) },
                chatAdmin: container.chatAdmin,
                makeBotApp: { container.botAppModel($0) },
                listActions: ChatProfileListActions(
                    muteFor: { choice in Task { await container.muteFor(id: id, choice) } },
                    folders: { container.folderChoices(id: id) },
                    toggleFolder: { folder in Task { await container.toggleFolder(id: id, folderId: folder) } },
                    createFolder: { title in Task { await container.createFolder(id: id, title: title) } }
                ),
                nowPlaying: container.nowPlaying
            ),
            actions: ChatScreenContext.Actions(
                toggleMute: { Task { await container.toggleMute(id: id) } },
                eraseChat: { clear, everyone in
                    Task {
                        let gone = await container.eraseChat(id: id, clearHistory: clear, forEveryone: everyone)
                        if gone { router.chatId = nil }
                    }
                },
                leave: {
                    Task {
                        if await container.leaveChat(id: id), router.chatId == id { router.chatId = nil }
                    }
                },
                openChat: { other in
                    if other != id { router.chatId = other }
                },
                openDialog: { draft in
                    container.openDialog(draft)
                    if draft.chatId != id { router.chatId = draft.chatId }
                },
                markUnread: { date in
                    Task {
                        if await container.markUnread(id: id, from: date), router.chatId == id { router.chatId = nil }
                    }
                },
                call: { peer, video in container.startCall(peer, video: video) },
                profileOpened: { if router.profileRequest == id { router.profileRequest = nil } },
                openVoice: openVoice
            )
        )
    }
}
