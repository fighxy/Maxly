import Foundation
import Observation
import OrbitleDomain

/// «Папки»: серверные папки чатов. «Все» стоит первой и не меняется, остальные можно
/// переименовать, удалить, переставить и наполнить чатами.
@MainActor
@Observable
public final class FoldersModel {
    /// Папки в порядке сервера, «Все» первой. `nil`, пока сервер их не прислал.
    public private(set) var folders: [ServerFolder]?
    public private(set) var isWorking = false
    public var errorMessage: String?

    @ObservationIgnored private let repository: any FolderRepository
    @ObservationIgnored private var watch: Task<Void, Never>?

    public init(repository: any FolderRepository) {
        self.repository = repository
    }

    public func activate() async {
        if watch == nil {
            let stream = repository.folders()
            watch = Task { [weak self] in
                for await list in stream {
                    guard let self else { return }
                    self.folders = Self.ordered(list)
                }
            }
        }
        do {
            try await repository.reload()
        } catch {
            Log.warning(.settings, "Папки не загрузились: \(error)")
            if folders == nil { errorMessage = "Не удалось загрузить папки. \(error.message)" }
        }
    }

    public func deactivate() {
        watch?.cancel()
        watch = nil
    }

    /// «Все» первой, остальные в порядке сервера.
    static func ordered(_ list: [ServerFolder]) -> [ServerFolder] {
        list.filter(\.isAllChats) + list.filter { !$0.isAllChats }
    }

    public var editable: [ServerFolder] { folders?.filter { !$0.isAllChats } ?? [] }
    public var allChats: ServerFolder? { folders?.first(where: \.isAllChats) }

    /// Папок по типам ещё нет: предлагаем создать «Личные», «Каналы» и «Боты».
    public var canAddTypeFolders: Bool {
        guard folders != nil else { return false }
        let existing = Set(editable.map { $0.title.lowercased() })
        return Self.typeFolders.contains { !existing.contains($0.title.lowercased()) }
    }

    /// Папки по типам чатов: фильтры сервера (4 диалоги, 2 каналы, 10 боты).
    public static let typeFolders: [(title: String, filters: [String])] = [
        ("Личные", ["4"]),
        ("Каналы", ["2"]),
        ("Боты", ["10"]),
    ]

    public func create(title: String, chatIds: [String]) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await work("Не удалось создать папку") {
            try await repository.create(title: name, chatIds: chatIds, filters: [])
            Log.info(.settings, "Папка создана: \(chatIds.count) чатов")
        }
    }

    public func addTypeFolders() async {
        let existing = Set(editable.map { $0.title.lowercased() })
        await work("Не удалось создать папки") {
            for folder in Self.typeFolders where !existing.contains(folder.title.lowercased()) {
                try await repository.create(title: folder.title, chatIds: [], filters: folder.filters)
            }
            Log.info(.settings, "Созданы папки по типам")
        }
    }

    public func rename(_ folder: ServerFolder, to title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isAllChats, !name.isEmpty, name != folder.title else { return }
        await work("Не удалось переименовать папку") {
            try await repository.rename(folderId: folder.id, title: name)
        }
    }

    public func setChats(_ folder: ServerFolder, chatIds: [String]) async {
        guard !folder.isAllChats else { return }
        await work("Не удалось сохранить чаты папки") {
            try await repository.setChats(folderId: folder.id, chatIds: chatIds)
        }
    }

    public func delete(_ folder: ServerFolder) async {
        guard !folder.isAllChats else { return }
        let before = folders
        folders?.removeAll { $0.id == folder.id }
        await work("Не удалось удалить папку", restoring: before) {
            try await repository.delete(folderId: folder.id)
            Log.info(.settings, "Папка удалена")
        }
    }

    /// Перестановка в списке редактируемых папок (без «Все»).
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        guard let current = folders else { return }
        var rest = current.filter { !$0.isAllChats }
        rest = Self.moving(rest, fromOffsets: source, toOffset: destination)
        let next = current.filter(\.isAllChats) + rest
        guard next.map(\.id) != current.map(\.id) else { return }
        folders = next
        await work("Не удалось изменить порядок папок", restoring: current) {
            try await repository.reorder(next.map(\.id))
        }
    }

    /// Как `move(fromOffsets:toOffset:)` из SwiftUI, но без SwiftUI.
    static func moving<T>(_ items: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        let moved = source.filter { $0 < items.count }.map { items[$0] }
        var rest: [T] = []
        var insertAt = 0
        for (index, item) in items.enumerated() where !source.contains(index) {
            if index < destination { insertAt += 1 }
            rest.append(item)
        }
        rest.insert(contentsOf: moved, at: min(insertAt, rest.count))
        return rest
    }

    private func work(
        _ failure: String,
        restoring previous: [ServerFolder]? = nil,
        _ body: () async throws -> Void
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
        } catch {
            if let previous { folders = previous }
            errorMessage = "\(failure). \((error as? OrbitleError ?? .unknown).message)"
        }
    }
}
