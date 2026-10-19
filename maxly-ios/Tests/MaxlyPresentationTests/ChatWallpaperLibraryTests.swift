import Foundation
import Testing
import MaxlyDomain
@testable import MaxlyPresentation

@Suite("Свои обои")
@MainActor
struct ChatWallpaperLibraryTests {
    @Test("Чат берёт свои обои, потом общие, без них — встроенные")
    func resolution() {
        let store = InMemoryCustomWallpaperStore()
        let library = ChatWallpaperLibrary(store: store)
        #expect(library.backdrop(chatId: "1") == nil)
        #expect(library.apply(image: Data([1]), dim: 0.2, blur: 0, for: .global))
        #expect(library.backdrop(chatId: "1")?.scope == .global)
        #expect(library.backdrop(chatId: "1")?.dim == 0.2)
        #expect(library.apply(image: Data([2]), dim: 0.4, blur: 0.5, for: .chat("1")))
        #expect(library.backdrop(chatId: "1")?.scope == .chat("1"))
        #expect(library.backdrop(chatId: "1")?.dim == 0.4)
        #expect(library.backdrop(chatId: "2")?.scope == .global)
        #expect(library.backdrop(for: .chat("2")) == nil)
        #expect(library.hasOwn(.chat("1")))
        #expect(!library.hasOwn(.chat("2")))
    }

    @Test("Сброс обоев чата удаляет картинку и возвращает общие")
    func reset() {
        let store = InMemoryCustomWallpaperStore()
        let library = ChatWallpaperLibrary(store: store)
        library.apply(image: Data([1]), dim: 0.1, blur: 0, for: .global)
        library.apply(image: Data([2]), dim: 0.1, blur: 0, for: .chat("5"))
        #expect(store.images.count == 2)
        library.reset(.chat("5"))
        #expect(store.images.count == 1)
        #expect(library.backdrop(chatId: "5")?.scope == .global)
        library.reset(.global)
        #expect(store.images.isEmpty)
        #expect(library.backdrop(chatId: "5") == nil)
        #expect(library.index.isEmpty)
    }

    @Test("Ошибка записи не меняет обои и даёт текст для экрана")
    func failure() {
        let library = ChatWallpaperLibrary(store: FailingStore())
        #expect(!library.apply(image: Data([1]), dim: 0.1, blur: 0, for: .global))
        #expect(library.errorMessage == "Не удалось сохранить обои")
        #expect(library.backdrop(chatId: nil) == nil)
    }

    @Test("Сохранённые обои читаются при запуске")
    func loadsSaved() {
        let saved = CustomWallpaperIndex(chats: ["9": CustomWallpaper(file: "chat-9-x.jpg", dim: 0.3)])
        let library = ChatWallpaperLibrary(store: InMemoryCustomWallpaperStore(saved))
        #expect(library.wallpaper(for: .chat("9"))?.file == "chat-9-x.jpg")
        #expect(library.backdrop(chatId: "9")?.url.lastPathComponent == "chat-9-x.jpg")
    }
}

@MainActor
private final class FailingStore: CustomWallpaperStore {
    struct Failure: Error {}
    func load() -> CustomWallpaperIndex { .empty }
    func url(for wallpaper: CustomWallpaper) -> URL { URL(fileURLWithPath: "/dev/null") }
    func save(image: Data, dim: Double, blur: Double, for scope: WallpaperScope) throws -> CustomWallpaper { throw Failure() }
    func remove(_ scope: WallpaperScope) {}
}
