import Foundation
import Observation
import MaxlyDomain

/// Свои фото обоев: общее («Оформление» → «Обои чата») и своё у чата («Ещё» → «Обои» в профиле).
/// Затемнение и размытие общие для всех фото.
///
/// Экран чата спрашивает `background(chatKey:)`: фото чата, затем «Без обоев» чата, затем общее
/// фото, иначе встроенные обои из «Оформления». Картинку сюда отдают уже уменьшенной.
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

    public static func chatKey(account: String, chatId: String) -> String {
        CustomWallpaperIndex.chatKey(account: account, chatId: chatId)
    }

    public var hasGlobalPhoto: Bool { index.global != nil }
    public var dimPercent: Int { index.dimPercent }
    public var blur: Bool { index.blur }

    public func choice(chatKey: String) -> ChatWallpaperChoice { index.choice(chatKey: chatKey) }

    /// Фон ленты чата; без ключа (чат не известен) — как в общих.
    public func background(chatKey: String?) -> ChatBackground {
        switch index.resolve(chatKey: chatKey) {
        case .photo(let file): .photo(backdrop(file))
        case .plain: .plain
        case .preset: .preset
        }
    }

    /// Общее фото для предпросмотра в «Оформлении».
    public var globalBackdrop: CustomWallpaperBackdrop? { index.global.map(backdrop) }

    /// Поставить готовую картинку для `scope`. `false` — не записалось, текст в `errorMessage`.
    @discardableResult
    public func setPhoto(_ image: Data, for scope: WallpaperScope) -> Bool {
        do {
            try store.savePhoto(image, for: scope)
            index = store.load()
            Log.info(.ui, "Своё фото обоев: \(Self.describe(scope)), \(image.count / 1024) КиБ")
            return true
        } catch {
            errorMessage = "Не удалось сохранить обои"
            Log.error(.ui, "Своё фото обоев не записано: \(error.localizedDescription)")
            return false
        }
    }

    /// «Как в общих» (фото чата удаляется) или «Без обоев» у чата.
    public func setChoice(_ choice: ChatWallpaperChoice, chatKey: String) {
        switch choice {
        case .global: store.setChat(chatKey, plain: false)
        case .plain: store.setChat(chatKey, plain: true)
        case .photo: return
        }
        index = store.load()
        Log.info(.ui, "Обои чата: \(choice == .plain ? "без обоев" : "как в общих")")
    }

    /// «Сбросить»: общее фото удаляется, остаются встроенные обои.
    public func resetGlobal() {
        guard index.global != nil else { return }
        store.resetGlobal()
        index = store.load()
        Log.info(.ui, "Общее фото обоев сброшено")
    }

    public func setDim(_ percent: Int) {
        let value = CustomWallpaperStyle.clampDim(percent)
        guard value != index.dimPercent else { return }
        store.setDim(value)
        index = store.load()
    }

    public func setBlur(_ blur: Bool) {
        guard blur != index.blur else { return }
        store.setBlur(blur)
        index = store.load()
        Log.info(.ui, "Размытие фото обоев: \(blur)")
    }

    private func backdrop(_ file: String) -> CustomWallpaperBackdrop {
        CustomWallpaperBackdrop(
            url: store.url(forFile: file),
            blurredURL: store.url(forFile: CustomWallpaperStyle.blurredName(file)),
            dimPercent: index.dimPercent,
            blur: index.blur
        )
    }

    private static func describe(_ scope: WallpaperScope) -> String {
        switch scope {
        case .global: "общее"
        case .chat: "чат"
        }
    }
}
