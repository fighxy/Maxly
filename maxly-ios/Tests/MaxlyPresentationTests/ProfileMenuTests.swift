import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Меню профиля как в Max")
struct ProfileMenuTests {
    private let folders = [ChatListMenu.FolderChoice(id: "n", title: "Новые", contains: false)]

    @Test("Человек: плитки и «Ещё»")
    func person() {
        let tiles = ProfileMenu.tiles(kind: .user)
        #expect(tiles.map(\.title) == ["Чат", "Звонок", "Видео", "Звук", "Ещё"])
        let more = ProfileMenu.entries(kind: .user, tiles: tiles, folders: folders, hasStories: true, canReport: true, blocked: false)
        #expect(more.map(\.title) == [
            "Поделиться контактом", "Добавить в папку", "Найти", "Стереть переписку",
            "Скрыть истории автора", "Заблокировать", "Удалить чат",
        ])
        #expect(more.filter(\.isDanger).map(\.title) == ["Заблокировать", "Удалить чат"])
    }

    @Test("Свой канал: «Отписаться» и «Удалить канал»")
    func ownChannel() {
        let tiles = ProfileMenu.tiles(kind: .channel)
        #expect(tiles.map(\.title) == ["Звук", "Ещё"])
        let more = ProfileMenu.entries(kind: .channel, tiles: tiles, folders: folders, canReport: true, isAdmin: true, isOwner: true)
        #expect(more.map(\.title) == ["Добавить в папку", "Найти", "Стереть переписку", "Отписаться от канала", "Удалить канал"])
    }

    @Test("Подписчик канала не удаляет канал, а жалуется")
    func subscriber() {
        let tiles = ProfileMenu.tiles(kind: .channel)
        let more = ProfileMenu.entries(kind: .channel, tiles: tiles, hasLink: true, folders: nil, canReport: true)
        #expect(more.map(\.title) == ["Поделиться ссылкой", "Найти", "Стереть переписку", "Пожаловаться", "Отписаться от канала"])
    }

    @Test("Группа со звонками")
    func group() {
        let tiles = ProfileMenu.tiles(kind: .group, groupCalls: true)
        #expect(tiles.map(\.title) == ["Звонок", "Видео", "Звук", "Найти", "Ещё"])
        let more = ProfileMenu.entries(kind: .group, tiles: tiles, folders: folders, canReport: true, isOwner: true)
        #expect(more.map(\.title) == ["Добавить в папку", "Стереть переписку", "Пожаловаться", "Покинуть группу", "Удалить группу"])
    }

    @Test("Канал из поиска: только «Подписаться»")
    func notListed() {
        let tiles = ProfileMenu.tiles(kind: .channel, listed: false)
        #expect(tiles == [.subscribe, .more])
        #expect(ProfileMenu.entries(kind: .channel, tiles: tiles, listed: false, hasLink: true, canReport: true) == [.shareLink, .report])
    }
}
