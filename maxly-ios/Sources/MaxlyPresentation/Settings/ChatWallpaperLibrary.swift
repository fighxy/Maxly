import Foundation
import Observation
import MaxlyDomain

/// Свои фото обоев: общие для всех чатов и отдельные для чата или канала.
///
/// Экран чата спрашивает `backdrop(chatId:)`: обои чата, иначе общие, иначе `nil` — тогда
/// остаются встроенные обои из «Оформления». Картинку сюда отдают уже готовой.
@MainActor
@Observable
public final class ChatWallpaperLibrary {
    public private(set) var index: CustomWallpaperIndex
    /// Последняя ошибка записи: экран показывает её и сбрасывает.
    public var errorMessage: String?

    @ObservationIgnored private let store: any CustomWallpaperStore

    public init(store: any CustomWallpaperStore) {
        self.store = store
        index = store.load()
    }

    /// Своё фото, заданное именно для `scope`.
    public func wallpaper(for scope: WallpaperScope) -> CustomWallpaper? { index[scope] }

    public func hasOwn(_ scope: WallpaperScope) -> Bool { index[scope] != nil }

    /// Что показать за лентой чата `chatId`; `nil` — встроенные обои.
    public func backdrop(chatId: String?) -> CustomWallpaperBackdrop? {
        guard let wallpaper = index.resolve(chatId: chatId) else { return nil }
        let scope: WallpaperScope = if let chatId, index.chats[chatId] != nil { .chat(chatId) } else { .global }
        return CustomWallpaperBackdrop(url: store.url(for: wallpaper), dim: wallpaper.dim, scope: scope)
    }

    /// Своё фото именно `scope` для показа (без подстановки общих).
    public func backdrop(for scope: WallpaperScope) -> CustomWallpaperBackdrop? {
        guard let wallpaper = index[scope] else { return nil }
        return CustomWallpaperBackdrop(url: store.url(for: wallpaper), dim: wallpaper.dim, scope: scope)
    }

    /// Поставить готовую картинку для `scope`. `false` — не записалось, текст в `errorMessage`.
    @discardableResult
    public func apply(image: Data, dim: Double, blur: Double, for scope: WallpaperScope) -> Bool {
        do {
            try store.save(image: image, dim: dim, blur: blur, for: scope)
            index = store.load()
            Log.info(.ui, "Свои обои: \(Self.describe(scope)), \(image.count / 1024) КиБ")
            return true
        } catch {
            errorMessage = "Не удалось сохранить обои"
            Log.error(.ui, "Свои обои не записаны: \(error.localizedDescription)")
            return false
        }
    }

    /// «Сбросить обои»: своё фото `scope` удаляется вместе с файлом.
    public func reset(_ scope: WallpaperScope) {
        guard index[scope] != nil else { return }
        store.remove(scope)
        index = store.load()
        Log.info(.ui, "Свои обои сброшены: \(Self.describe(scope))")
    }

    private static func describe(_ scope: WallpaperScope) -> String {
        switch scope {
        case .global: "общие"
        case .chat: "чат"
        }
    }
}
