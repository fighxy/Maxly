import SwiftUI
import MaxlyPresentation

/// Одна сессия истории на экран. Обогащение привязано к составу ленты,
/// а не к числу сообщений: скользящее окно может сохранять прежний размер.
struct ChatHistoryLifecycle: ViewModifier {
    let model: ChatViewModel
    let requestsComments: Bool

    private struct Request: Equatable {
        let version: Int
        let restoring: Bool
        let comments: Bool
    }

    func body(content: Content) -> some View {
        content
            .task(id: model.chatId) {
                model.activate()
                await model.loadLatest()
            }
            .onDisappear { model.deactivate() }
            .task(id: Request(version: model.transcriptVersion,
                              restoring: model.isRestoringHistory,
                              comments: requestsComments)) {
                guard !model.isRestoringHistory, !model.messages.isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
                guard !Task.isCancelled else { return }
                model.requestReactions(for: model.messages)
                if requestsComments { model.requestCommentCounts(for: model.messages) }
            }
    }
}
