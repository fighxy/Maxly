import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Подтверждения из меню строки списка чатов: блокировка, остановка и удаление бота, жалоба.
struct ChatListRowDialogs: ViewModifier {
    @Bindable var viewModel: ChatListViewModel
    @Binding var blockCandidate: ChatListItem?
    @Binding var botStopCandidate: ChatListItem?
    @Binding var botDeleteCandidate: ChatListItem?
    @Binding var botReport: BotReport?
    @Environment(\.privateMode) private var privateMode

    func body(content: Content) -> some View {
        content
        .confirmationDialog(
            blockTitle,
            isPresented: Binding(get: { blockCandidate != nil }, set: { if !$0 { blockCandidate = nil } }),
            titleVisibility: .visible,
            presenting: blockCandidate
        ) { item in
            Button("Заблокировать", role: .destructive) { Task { await viewModel.block(chatId: item.id) } }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Он не сможет писать вам и звонить. Разблокировать можно в настройках конфиденциальности.")
        }
        .confirmationDialog(
            botTitle(botStopCandidate, "Остановить"),
            isPresented: Binding(get: { botStopCandidate != nil }, set: { if !$0 { botStopCandidate = nil } }),
            titleVisibility: .visible,
            presenting: botStopCandidate
        ) { item in
            Button("Остановить", role: .destructive) { Task { await viewModel.stopBot(chatId: item.id) } }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Бот больше не сможет писать вам. Перезапустить его можно в меню чата.")
        }
        .confirmationDialog(
            botTitle(botDeleteCandidate, "Удалить чат и остановить"),
            isPresented: Binding(get: { botDeleteCandidate != nil }, set: { if !$0 { botDeleteCandidate = nil } }),
            titleVisibility: .visible,
            presenting: botDeleteCandidate
        ) { item in
            Button("Удалить и остановить", role: .destructive) { Task { await viewModel.deleteAndStopBot(chatId: item.id) } }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Переписка удалится у вас, бот больше не сможет писать вам.")
        }
        .confirmationDialog(
            botTitle(botReport?.item, "Пожаловаться на"),
            isPresented: Binding(get: { botReport?.reasons.isEmpty == false }, set: { if !$0 { botReport = nil } }),
            titleVisibility: .visible,
            presenting: botReport
        ) { report in
            ForEach(report.reasons) { reason in
                Button(reason.title.isEmpty ? "Причина \(reason.id)" : reason.title) {
                    Task { await viewModel.reportBot(chatId: report.item.id, reasonId: reason.id) }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// «Остановить бота?» / «Остановить «Имя»?»; в приватном режиме без имени.
    private func botTitle(_ item: ChatListItem?, _ verb: String) -> String {
        guard let item, privateMode == .visible else { return "\(verb) бота?" }
        return verb == "Пожаловаться на" ? "\(verb) «\(item.title)»" : "\(verb) «\(item.title)»?"
    }

    private var blockTitle: String {
        guard let item = blockCandidate, privateMode == .visible else { return "Заблокировать пользователя?" }
        return "Заблокировать \(item.title)?"
    }
}

/// Удаление и очистка чата из меню и свайпа строки: «только у меня» или «у всех».
struct ChatListEraseDialogs: ViewModifier {
    @Bindable var viewModel: ChatListViewModel
    @Environment(\.privateMode) private var privateMode

    func body(content: Content) -> some View {
        content
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionShown,
            titleVisibility: .visible,
            presenting: viewModel.deletionCandidate
        ) { item in
            eraseButtons(item, clearing: false)
            Button("Отмена", role: .cancel) { viewModel.cancelDelete() }
        }
        .confirmationDialog(
            clearTitle,
            isPresented: clearShown,
            titleVisibility: .visible,
            presenting: viewModel.clearCandidate
        ) { item in
            eraseButtons(item, clearing: true)
            Button("Отмена", role: .cancel) { viewModel.cancelClear() }
        }
        // Несколько чатов из режима правки: удаляются только у себя.
        .confirmationDialog(
            bulkTitle,
            isPresented: bulkShown,
            titleVisibility: .visible,
            presenting: viewModel.bulkDeletion
        ) { ids in
            Button("Удалить у меня", role: .destructive) {
                Task { await viewModel.confirmBulkDelete(ids) }
            }
            Button("Отмена", role: .cancel) { viewModel.cancelBulkDelete() }
        } message: { _ in
            Text("Чаты удалятся только у вас.")
        }
    }

    private var bulkShown: Binding<Bool> {
        Binding(
            get: { viewModel.bulkDeletion != nil },
            set: { if !$0 { viewModel.cancelBulkDelete() } }
        )
    }

    private var bulkTitle: String {
        "Удалить \(ChatListViewModel.chatCount(viewModel.bulkDeletion?.count ?? 0))?"
    }

    private var deletionShown: Binding<Bool> {
        Binding(
            get: { viewModel.deletionCandidate != nil },
            set: { if !$0 { viewModel.cancelDelete() } }
        )
    }

    private var deletionTitle: String {
        guard let item = viewModel.deletionCandidate else { return "" }
        // Название чата не должно всплыть в диалоге, пока включён приватный режим.
        if privateMode.isMasked { return "Удалить этот чат?" }
        return "Удалить чат «\(item.title)»?"
    }

    private var clearShown: Binding<Bool> {
        Binding(
            get: { viewModel.clearCandidate != nil },
            set: { if !$0 { viewModel.cancelClear() } }
        )
    }

    private var clearTitle: String {
        "Стереть переписку?"
    }

    /// «Только у меня» всегда. «У всех» — кроме «Избранного», где собеседника нет.
    /// Кнопки передают id чата сами: к началу задачи диалог уже закрыт и кандидат сброшен.
    @ViewBuilder
    private func eraseButtons(_ item: ChatListItem, clearing: Bool) -> some View {
        let saved = item.id == Chat.savedMessagesId
        if !saved {
            let everyone = clearing
                ? (item.type == .private ? "Очистить у меня и у собеседника" : "Очистить у всех")
                : (item.type == .private ? "Удалить у меня и у собеседника" : "Удалить у всех")
            Button(everyone, role: .destructive) {
                Task {
                    if clearing { await viewModel.confirmClear(chatId: item.id, forEveryone: true) }
                    else { await viewModel.confirmDelete(chatId: item.id, forEveryone: true) }
                }
            }
        }
        Button(clearing ? (saved ? "Очистить" : "Очистить только у меня") : (saved ? "Удалить" : "Удалить только у меня"), role: .destructive) {
            Task {
                if clearing { await viewModel.confirmClear(chatId: item.id, forEveryone: false) }
                else { await viewModel.confirmDelete(chatId: item.id, forEveryone: false) }
            }
        }
    }
}

/// Жалоба на бота из меню строки: чат и причины сервера.
struct BotReport: Identifiable {
    let item: ChatListItem
    let reasons: [ComplaintReason]
    var id: String { item.id }
}

