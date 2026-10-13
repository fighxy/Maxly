import SwiftUI
import MaxlyPresentation

/// Подменю «Добавить в папку», как в Max: папки (галочка — чат уже там, повтор — убрать),
/// черта и «Создать папку».
struct FolderMenu: View {
    let folders: [ChatListMenu.FolderChoice]
    let onToggle: (String) -> Void
    let onCreate: () -> Void

    var body: some View {
        Menu {
            ForEach(folders) { folder in
                Button { onToggle(folder.id) } label: {
                    Label(folder.title, systemImage: folder.contains ? "checkmark" : "folder")
                }
            }
            if !folders.isEmpty { Divider() }
            Button(action: onCreate) {
                Label(ChatListMenu.createFolder, systemImage: "plus")
            }
        } label: {
            Label("Добавить в папку", systemImage: "folder.badge.plus")
        }
    }
}

/// Окно с названием новой папки: чат попадает в неё сразу.
struct CreateFolderAlert: ViewModifier {
    @Binding var chatId: String?
    let onCreate: (String, String) -> Void
    @State private var title = ""

    func body(content: Content) -> some View {
        content.alert(
            "Новая папка",
            isPresented: Binding(get: { chatId != nil }, set: { if !$0 { chatId = nil } })
        ) {
            TextField("Название папки", text: $title)
            Button("Создать") {
                if let chatId { onCreate(chatId, title) }
                title = ""
            }
            Button("Отмена", role: .cancel) { title = "" }
        }
    }
}

extension View {
    func createFolderAlert(for chatId: Binding<String?>, onCreate: @escaping (String, String) -> Void) -> some View {
        modifier(CreateFolderAlert(chatId: chatId, onCreate: onCreate))
    }
}
