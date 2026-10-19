import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Свои обои")
@MainActor
struct ChatWallpaperLibraryTests {
    private let chat = ChatWallpaperLibrary.chatKey(account: "7", chatId: "1")
    private let other = ChatWallpaperLibrary.chatKey(account: "7", chatId: "2")

    @Test("Фото чата, «Без обоев» чата, общее фото, встроенные — по порядку")
    func resolution() {
        let store = InMemoryCustomWallpaperStore()
        let library = ChatWallpaperLibrary(store: store)
        #expect(library.background(chatKey: chat) == .preset)
        #expect(library.setPhoto(Data([1]), for: .global))
        #expect(library.background(chatKey: chat).photo != nil)
        library.setChoice(.plain, chatKey: chat)
        #expect(library.background(chatKey: chat) == .plain)
        #expect(library.background(chatKey: other).photo == library.globalBackdrop)
        #expect(library.setPhoto(Data([2]), for: .chat(chat)))
        #expect(library.choice(chatKey: chat) == .photo("wallpaper-2.jpg"))
        #expect(library.background(chatKey: chat).photo?.url.lastPathComponent == "wallpaper-2.jpg")
        library.setChoice(.global, chatKey: chat)
        #expect(store.images.keys.sorted() == ["wallpaper-1.jpg"])
        #expect(library.background(chatKey: chat).photo?.url.lastPathComponent == "wallpaper-1.jpg")
    }

    @Test("Затемнение и размытие общие для всех фото")
    func sharedStyle() {
        let library = ChatWallpaperLibrary(store: InMemoryCustomWallpaperStore())
        library.setPhoto(Data([1]), for: .global)
        library.setPhoto(Data([2]), for: .chat(chat))
        library.setDim(90)
        library.setBlur(true)
        #expect(library.dimPercent == 60)
        for key in [chat, other] {
            let photo = library.background(chatKey: key).photo
            #expect(photo?.dimPercent == 60)
            #expect(photo?.blur == true)
            #expect(photo?.blurredURL.lastPathComponent.hasPrefix("blur-") == true)
        }
    }

    @Test("«Сбросить» убирает общее фото и его файл")
    func reset() {
        let store = InMemoryCustomWallpaperStore()
        let library = ChatWallpaperLibrary(store: store)
        library.setPhoto(Data([1]), for: .global)
        #expect(library.hasGlobalPhoto)
        library.resetGlobal()
        #expect(!library.hasGlobalPhoto)
        #expect(store.images.isEmpty)
        #expect(library.background(chatKey: chat) == .preset)
    }

    @Test("Ошибка записи не меняет обои и даёт текст для экрана")
    func failure() {
        let library = ChatWallpaperLibrary(store: FailingStore())
        #expect(!library.setPhoto(Data([1]), for: .global))
        #expect(library.errorMessage == "Не удалось сохранить обои")
        #expect(library.background(chatKey: nil) == .preset)
    }
}

@MainActor
private final class FailingStore: CustomWallpaperStore {
    struct Failure: Error {}
    func load() -> CustomWallpaperIndex { .empty }
    func url(forFile file: String) -> URL { URL(fileURLWithPath: "/dev/null") }
    func savePhoto(_ image: Data, for scope: WallpaperScope) throws -> String { throw Failure() }
    func setChat(_ chatKey: String, plain: Bool) {}
    func resetGlobal() {}
    func setDim(_ percent: Int) {}
    func setBlur(_ blur: Bool) {}
}
