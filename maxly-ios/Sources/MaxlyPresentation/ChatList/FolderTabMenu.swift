import Foundation

/// Меню папки над списком чатов (долгое нажатие на вкладку), как в Telegram. «Все»: «Настроить
/// папки», «Прочитать все» (есть непрочитанные), «Изменить порядок». Своя папка: «Настроить папку», «Добавить чаты», «Прочитать все»
/// (есть непрочитанные), «Выкл. уведомления» / «Вкл. уведомления», «Удалить», «Изменить
/// порядок». Порядок — только когда своих папок больше одной. Тот же состав, что у Android и ПК.
public enum FolderTabMenu {
    public enum Entry: Hashable, Sendable {
        /// «Все»: экран папок целиком.
        case editFolders
        /// Название и чаты этой папки.
        case editFolder
        case addChats
        case readAll
        /// `muted` — у всех чатов папки звук уже выключен: пункт его включает.
        case mute(muted: Bool)
        case delete
        case reorder

        public var title: String {
            switch self {
            case .editFolders: "Настроить папки"
            case .editFolder: "Настроить папку"
            case .addChats: "Добавить чаты"
            case .readAll: "Прочитать все"
            case .mute(let muted): muted ? "Вкл. уведомления" : "Выкл. уведомления"
            case .delete: "Удалить"
            case .reorder: "Изменить порядок"
            }
        }

        public var isDanger: Bool { self == .delete }

        /// Перед пунктом разделитель: «Изменить порядок» отделён от остальных.
        public var separated: Bool { self == .reorder }
    }

    /// Пункты для вкладки. `editable` — папка с сервера и её можно менять (локальные вкладки-
    /// фильтры нельзя). `folderCount` — сколько своих папок, кроме «Все».
    public static func entries(
        isAll: Bool,
        editable: Bool,
        hasUnread: Bool,
        allMuted: Bool,
        hasChats: Bool,
        folderCount: Int
    ) -> [Entry] {
        let reorder: [Entry] = folderCount > 1 ? [.reorder] : []
        if isAll {
            return (editable ? [.editFolders] : []) + (hasUnread ? [.readAll] : []) + (editable ? reorder : [])
        }
        var entries: [Entry] = []
        if editable { entries += [.editFolder, .addChats] }
        if hasUnread { entries.append(.readAll) }
        if hasChats { entries.append(.mute(muted: allMuted)) }
        if editable { entries += [.delete] + reorder }
        return entries
    }
}
