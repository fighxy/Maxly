import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// «Папки»: серверные папки чатов. «Все» не меняется, остальные переставляются,
/// переименовываются, удаляются и наполняются чатами.
struct FoldersView: View {
    @Bindable var model: FoldersModel
    @Bindable var list: ChatListViewModel
    @State private var renaming: ServerFolder?
    @State private var newTitle = ""
    @State private var picking: ServerFolder?
    @State private var creating = false
    @State private var deleting: ServerFolder?

    var body: some View {
        List {
            if let folders = model.folders {
                if let all = model.allChats {
                    Section {
                        LabeledContent {
                            Text("\(count(all))")
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(all.title.isEmpty ? "Все" : all.title)
                                Text("Все чаты, кроме архива")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    ForEach(model.editable) { folder in
                        row(folder)
                    }
                    .onMove { source, destination in
                        Task { await model.move(fromOffsets: source, toOffset: destination) }
                    }
                    .onDelete { offsets in
                        deleting = offsets.first.map { model.editable[$0] }
                    }
                } header: {
                    if !model.editable.isEmpty { Text("Мои папки") }
                } footer: {
                    if folders.count > 1 {
                        Text("Папки видны над списком чатов и на других устройствах. Порядок меняется кнопкой «Изменить».")
                    }
                }
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("Создать папку", systemImage: "folder.badge.plus")
                    }
                    if model.canAddTypeFolders {
                        Button {
                            Task { await model.addTypeFolders() }
                        } label: {
                            Label("Добавить папки по типам", systemImage: "square.stack.3d.up")
                        }
                    }
                } footer: {
                    if model.canAddTypeFolders {
                        Text("«Личные», «Каналы» и «Боты» наполняются сами по типу чата.")
                    }
                }
                .disabled(model.isWorking)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle("Папки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.editable.isEmpty { EditButton() }
        }
        .task { await model.activate() }
        .onDisappear { model.deactivate() }
        .alert("Переименовать папку", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Название", text: $newTitle)
            Button("Сохранить") {
                if let folder = renaming { Task { await model.rename(folder, to: newTitle) } }
            }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить папку «\(deleting?.title ?? "")»?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить папку", role: .destructive) {
                if let folder = deleting { Task { await model.delete(folder) } }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Чаты останутся в списке «Все».")
        }
        .sheet(item: $picking) { folder in
            ChatPickerSheet(title: folder.title, chats: pickable, initial: Set(folder.chatIds), askTitle: false) { _, ids in
                Task { await model.setChats(folder, chatIds: ids) }
            }
        }
        .sheet(isPresented: $creating) {
            ChatPickerSheet(title: "Новая папка", chats: pickable, initial: [], askTitle: true) { title, ids in
                Task { await model.create(title: title, chatIds: ids) }
            }
        }
        .alert(
            "Не получилось",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func row(_ folder: ServerFolder) -> some View {
        LabeledContent {
            Text("\(count(folder))")
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                if !folder.filters.isEmpty {
                    Text(filterSummary(folder))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button {
                newTitle = folder.title
                renaming = folder
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }
            Button {
                picking = folder
            } label: {
                Label("Выбрать чаты", systemImage: "checklist")
            }
            Button(role: .destructive) {
                deleting = folder
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    /// Чаты для выбора: весь список без архива.
    private var pickable: [Chat] {
        list.chats.filter { !$0.isArchived }
    }

    private func count(_ folder: ServerFolder) -> Int {
        let rule = folder.isAllChats ? ChatFolder.all : folder.chatFolder
        return list.chats.filter(rule.contains).count
    }

    private func filterSummary(_ folder: ServerFolder) -> String {
        let names: [ChatFolderRules.Code: String] = [
            .dialog: "личные", .contact: "контакты", .notContact: "не контакты", .group: "группы",
            .channel: "каналы", .bot: "боты", .unread: "непрочитанные", .markedUnread: "непрочитанные",
            .read: "прочитанные", .muted: "без звука", .notMuted: "со звуком",
        ]
        let codes = folder.filters.compactMap(ChatFolderRules.Code.init(text:))
        var seen: [String] = []
        for code in codes { if let name = names[code], !seen.contains(name) { seen.append(name) } }
        return seen.isEmpty ? "По правилам сервера" : "Сами: " + seen.joined(separator: ", ")
    }
}

/// Выбор чатов папки: весь список с галочками и поиском. Для новой папки — ещё и название.
struct ChatPickerSheet: View {
    let title: String
    let chats: [Chat]
    let initial: Set<String>
    let askTitle: Bool
    let onDone: (String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var name = ""
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if askTitle {
                    Section("Название") {
                        TextField("Например, Работа", text: $name)
                    }
                }
                Section {
                    ForEach(filtered) { chat in
                        Button {
                            if selection.contains(chat.id) { selection.remove(chat.id) } else { selection.insert(chat.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(title: chat.title, id: chat.id, url: chat.avatarURL, size: 36)
                                Text(chat.isSavedMessages ? "Избранное" : chat.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: selection.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(chat.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                    .font(.title3)
                            }
                        }
                        .accessibilityAddTraits(selection.contains(chat.id) ? .isSelected : [])
                    }
                } header: {
                    Text("Чаты · выбрано \(selection.count)")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск чатов")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        // Чаты папки, которых нет в списке (ещё не загружены), не теряются.
                        let known = Set(chats.map(\.id))
                        let hidden = initial.filter { !known.contains($0) }.sorted()
                        onDone(name, chats.map(\.id).filter(selection.contains) + hidden)
                        dismiss()
                    }
                    .disabled(askTitle && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { selection = initial }
        }
    }

    private var filtered: [Chat] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return chats }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(text) }
    }
}
