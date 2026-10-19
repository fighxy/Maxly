import Foundation
import Testing
import MaxlyDomain

@Suite("Фото профиля на весь экран")
struct ProfilePhotoURLTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test("Размер fn снимается, остальные параметры остаются")
    func stripsSize() {
        #expect(ProfilePhotoURL.withoutSize(url("https://i.cdn.test/i?r=AbC&fn=sqr_288")) == url("https://i.cdn.test/i?r=AbC"))
        #expect(ProfilePhotoURL.withoutSize(url("https://i.cdn.test/p&fn=sqr_96")) == url("https://i.cdn.test/p"))
        #expect(ProfilePhotoURL.withoutSize(url("https://i.cdn.test/i?fn=w_480&r=1&expires=9")) == url("https://i.cdn.test/i?r=1&expires=9"))
        #expect(ProfilePhotoURL.withoutSize(url("https://i.cdn.test/i?r=1&fn=sqr_96&fn=w_1080")) == url("https://i.cdn.test/i?r=1"))
    }

    @Test("Адрес без fn и похожие параметры не меняются")
    func keepsOthers() {
        let plain = url("https://i.cdn.test/i?r=1&fnord=2")
        #expect(ProfilePhotoURL.withoutSize(plain) == plain)
        let file = URL(fileURLWithPath: "/tmp/a&fn=sqr_96.jpg")
        #expect(ProfilePhotoURL.withoutSize(file) == file)
    }

    @Test("Снимок целиком важнее квадрата, без обоих — ничего")
    func prefersRaw() {
        let avatar = url("https://i.cdn.test/a?r=1")
        let raw = url("https://i.cdn.test/raw?r=2&fn=w_720")
        #expect(ProfilePhotoURL.full(avatar: avatar, raw: raw) == url("https://i.cdn.test/raw?r=2"))
        #expect(ProfilePhotoURL.full(avatar: avatar, raw: nil) == avatar)
        #expect(ProfilePhotoURL.full(avatar: nil, raw: nil) == nil)
    }

    @Test("Порядок загрузки: оригинал, потом размеры сервера, без повторов")
    func candidates() {
        let avatar = url("https://i.cdn.test/a?r=1&fn=sqr_96")
        let big = url("https://i.cdn.test/a?r=1&fn=w_1440")
        let small = url("https://i.cdn.test/a?r=1&fn=sqr_720")
        #expect(ProfilePhotoURL.candidates(avatar: avatar, raw: nil, viewer: [big, small, big]) == [url("https://i.cdn.test/a?r=1"), big, small])
        #expect(ProfilePhotoURL.candidates(avatar: nil, raw: nil, viewer: [big]) == [big])
        #expect(ProfilePhotoURL.candidates(avatar: nil, raw: nil, viewer: []).isEmpty)
    }

    @Test("Карточка чата открывает снимок целиком, если он есть")
    func chatProfile() {
        var profile = ChatProfile(kind: .channel, chatId: "-5", title: "Новости", avatarURL: url("https://i.cdn.test/c?r=1&fn=sqr_192"))
        #expect(profile.fullPhotoURL == url("https://i.cdn.test/c?r=1"))
        profile.photoURL = url("https://i.cdn.test/craw?r=1")
        #expect(profile.fullPhotoURL == url("https://i.cdn.test/craw?r=1"))
        #expect(ChatProfile(kind: .group, chatId: "-6", title: "Без фото").fullPhotoURL == nil)
        let sized = url("https://i.cdn.test/craw?r=1&fn=w_1440")
        let card = ChatProfile(kind: .user, chatId: "7", title: "Анна", photoURL: url("https://i.cdn.test/craw?r=1"), photoViewerURLs: [sized])
        #expect(card.photoCandidates == [url("https://i.cdn.test/craw?r=1"), sized])
        #expect(ChatProfile(kind: .user, chatId: "8", title: "Борис").photoViewerURLs == nil)
    }
}
