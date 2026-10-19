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

    @Test("Карточка чата открывает снимок целиком, если он есть")
    func chatProfile() {
        var profile = ChatProfile(kind: .channel, chatId: "-5", title: "Новости", avatarURL: url("https://i.cdn.test/c?r=1&fn=sqr_192"))
        #expect(profile.fullPhotoURL == url("https://i.cdn.test/c?r=1"))
        profile.photoURL = url("https://i.cdn.test/craw?r=1")
        #expect(profile.fullPhotoURL == url("https://i.cdn.test/craw?r=1"))
        #expect(ChatProfile(kind: .group, chatId: "-6", title: "Без фото").fullPhotoURL == nil)
    }
}
