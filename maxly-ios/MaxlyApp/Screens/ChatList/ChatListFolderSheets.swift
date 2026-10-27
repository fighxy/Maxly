import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Окна из меню вкладки папки: выбор чатов, экран «Папки», подтверждение удаления.
struct ChatListFolderSheets: ViewModifier {
    @Bindable var viewModel: ChatListViewModel
    /// Экран «Папки» для «Настроить папки» и «Изменить порядок»; `nil` — их нет.
    var makeFoldersModel: (() -> FoldersModel)?
    @Binding var folderEdit: ChatListView.FolderEdit?
    @Binding var foldersScreen: ChatListView.FoldersScreenRequest?
    @Binding var folderDelete: ServerFolder?

    func body(content: Content) -> some View {
        content
        .sheet(item: $folderEdit) { edit in
            if let folder = viewModel.serverFolder(edit.id) {
                ChatPickerSheet(
                    title: edit.withTitle ? "Папка" : folder.title,
                    chats: viewModel.chats.filter { !$0.isArchived },
                    initial: Set(folder.chatIds),
                    askTitle: edit.withTitle,
                    initialTitle: folder.title
                ) { title, ids in
                    Task { await viewModel.saveFolder(edit.id, title: edit.withTitle ? title : "", chatIds: ids) }
                }
            }
        }
        .sheet(item: $foldersScreen) { request in
            if let makeFoldersModel {
                NavigationStack {
                    FoldersView(model: makeFoldersModel(), list: viewModel, startsEditing: request.editing)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Закрыть") { foldersScreen = nil }
                            }
                        }
                }
            }
        }
        .confirmationDialog(
            "Удалить папку «\(folderDelete?.title ?? "")»?",
            isPresented: Binding(get: { folderDelete != nil }, set: { if !$0 { folderDelete = nil } }),
            titleVisibility: .visible,
            presenting: folderDelete
        ) { folder in
            Button("Удалить папку", role: .destructive) { Task { await viewModel.deleteFolder(folder.id) } }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Чаты останутся в списке «Все».")
        }
    }
}

extension ChatListView {
    struct FolderEdit: Identifiable {
        let id: String
        /// «Настроить папку» — с названием; «Добавить чаты» — только чаты.
        let withTitle: Bool
    }

    struct FoldersScreenRequest: Identifiable {
        let editing: Bool
        var id: Bool { editing }
    }
}
