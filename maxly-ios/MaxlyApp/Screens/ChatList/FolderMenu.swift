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

/// Пункты меню вкладки папки (`FolderTabMenu`), как в Telegram: «Удалить» красным, «Изменить
/// порядок» отдельной секцией внизу.
struct FolderTabMenuItems: View {
    let entries: [FolderTabMenu.Entry]
    let onPick: (FolderTabMenu.Entry) -> Void

    var body: some View {
        Section {
            ForEach(entries.filter { !$0.separated }, id: \.self, content: button)
        }
        let tail = entries.filter(\.separated)
        if !tail.isEmpty {
            Section {
                ForEach(tail, id: \.self, content: button)
            }
        }
    }

    private func button(_ entry: FolderTabMenu.Entry) -> some View {
        Button(role: entry.isDanger ? .destructive : nil) {
            onPick(entry)
        } label: {
            Label(entry.title, systemImage: Self.icon(entry))
        }
    }

    private static func icon(_ entry: FolderTabMenu.Entry) -> String {
        switch entry {
        case .editFolders, .editFolder: "square.and.pencil"
        case .addChats: "plus"
        case .readAll: "envelope.open"
        case .mute(let muted): muted ? "bell" : "bell.slash"
        case .delete: "trash"
        case .reorder: "arrow.up.arrow.down"
        }
    }
}
