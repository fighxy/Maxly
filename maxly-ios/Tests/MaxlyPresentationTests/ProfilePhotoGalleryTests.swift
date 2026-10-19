import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@MainActor
@Suite("История фото профиля")
struct ProfilePhotoGalleryTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    private actor Pages {
        var requests: [Int] = []
        let pages: [Int: ProfilePhotoPage]
        init(_ pages: [Int: ProfilePhotoPage]) { self.pages = pages }
        func page(_ from: Int) -> ProfilePhotoPage {
            requests.append(from)
            return pages[from] ?? ProfilePhotoPage(photos: [], total: 0)
        }
    }

    private func photo(_ n: Int) -> ProfilePhoto {
        ProfilePhoto(id: "\(n)", url: url("https://i.cdn.test/p\(n)"), viewerURLs: [url("https://i.cdn.test/p\(n)&fn=w_1440")])
    }

    @Test("Текущее фото первым, история страницами, повтор текущего пропущен")
    func pages() async {
        let current = url("https://i.cdn.test/p1")
        let pages = Pages([
            0: ProfilePhotoPage(photos: [photo(1), photo(2), photo(3)], total: 5),
            3: ProfilePhotoPage(photos: [photo(4), photo(5)], total: 5),
        ])
        let gallery = ProfilePhotoGallery(
            current: .init(id: "tile", candidates: [current]),
            idPrefix: "tile",
            loader: { (from: Int) async throws(MaxlyError) -> ProfilePhotoPage in await pages.page(from) }
        )
        #expect(gallery.total == 1)
        await gallery.loadMore()
        #expect(gallery.items.map(\.id) == ["tile", "tile-2", "tile-3"])
        #expect(gallery.total == 5)
        #expect(gallery.candidates(for: "tile-2") == [url("https://i.cdn.test/p2"), url("https://i.cdn.test/p2&fn=w_1440")])
        await gallery.shown("tile-2")
        #expect(gallery.items.count == 5)
        #expect(gallery.total == 5)
        await gallery.shown("tile-5")
        #expect(await pages.requests == [0, 3])
    }

    @Test("Без загрузчика — только текущее фото; отказ сервера не повторяется")
    func singleAndFailure() async {
        let alone = ProfilePhotoGallery(current: .init(id: "g", candidates: [url("https://i.cdn.test/g")]), idPrefix: "g", loader: nil)
        await alone.loadMore()
        #expect(alone.items.count == 1)
        #expect(alone.total == 1)

        let failing = ProfilePhotoGallery(
            current: .init(id: "u", candidates: [url("https://i.cdn.test/u")]),
            idPrefix: "u",
            loader: { (_: Int) async throws(MaxlyError) -> ProfilePhotoPage in throw .networkUnavailable }
        )
        await failing.loadMore()
        await failing.loadMore()
        #expect(failing.items.count == 1)
    }

    @Test("Галерея из карточки: у человека история, у группы только значок")
    func fromProfile() async {
        let user = ChatProfileViewModel(chatId: "5", title: "Анна", avatarURL: url("https://i.cdn.test/a&fn=sqr_96"), kind: .user, repository: NoProfiles())
        #expect(user.photoGallery(tileId: "t")?.items.first?.candidates == [url("https://i.cdn.test/a")])
        let none = ChatProfileViewModel(chatId: "6", title: "Без фото", repository: NoProfiles())
        #expect(none.photoGallery(tileId: "t") == nil)
    }
}

private struct NoProfiles: ChatProfileRepository {
    func profile(chatId: String) async throws(MaxlyError) -> ChatProfile { throw .networkUnavailable }
}
