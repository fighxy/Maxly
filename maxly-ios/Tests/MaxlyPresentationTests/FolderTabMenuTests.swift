import Testing
@testable import MaxlyPresentation

@Suite("Меню вкладки папки")
struct FolderTabMenuTests {
    @Test("«Все»: настроить папки, прочитать все при непрочитанных, порядок — только при двух своих папках")
    func allTab() {
        #expect(FolderTabMenu.entries(isAll: true, editable: true, hasUnread: true, allMuted: false, hasChats: true, folderCount: 2)
            == [.editFolders, .readAll, .reorder])
        #expect(FolderTabMenu.entries(isAll: true, editable: true, hasUnread: false, allMuted: false, hasChats: true, folderCount: 1)
            == [.editFolders])
        #expect(FolderTabMenu.entries(isAll: true, editable: false, hasUnread: true, allMuted: false, hasChats: true, folderCount: 3)
            == [.readAll])
        #expect(FolderTabMenu.entries(isAll: true, editable: false, hasUnread: false, allMuted: false, hasChats: true, folderCount: 3)
            .isEmpty)
    }

    @Test("Своя папка: привычный порядок, «Удалить» красным, порядок отдельно")
    func ownFolder() {
        let entries = FolderTabMenu.entries(isAll: false, editable: true, hasUnread: true, allMuted: false, hasChats: true, folderCount: 3)
        #expect(entries.map(\.title) == ["Настроить папку", "Добавить чаты", "Прочитать все", "Выкл. уведомления", "Удалить", "Изменить порядок"])
        #expect(FolderTabMenu.Entry.delete.isDanger)
        #expect(FolderTabMenu.Entry.reorder.separated)
    }

    @Test("«Прочитать все» только с непрочитанными, звук включается обратно")
    func readAndMute() {
        let entries = FolderTabMenu.entries(isAll: false, editable: true, hasUnread: false, allMuted: true, hasChats: true, folderCount: 1)
        #expect(entries == [.editFolder, .addChats, .mute(muted: true), .delete])
        #expect(FolderTabMenu.Entry.mute(muted: true).title == "Вкл. уведомления")
    }

    @Test("Локальная вкладка-фильтр: только прочитать и звук")
    func localFilter() {
        let entries = FolderTabMenu.entries(isAll: false, editable: false, hasUnread: true, allMuted: false, hasChats: true, folderCount: 0)
        #expect(entries == [.readAll, .mute(muted: false)])
    }
}
