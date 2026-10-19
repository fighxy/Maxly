import SwiftUI
import MaxlyDomain

private struct ChatWallpaperKey: EnvironmentKey {
    static let defaultValue: ChatWallpaper = .standard
}

private struct ChatPhotoWallpaperKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Обои чата из «Оформления». Корень приложения кладёт сюда выбор, лента рисует их за
    /// пузырями, а пузыри подстраивают подложку.
    var chatWallpaper: ChatWallpaper {
        get { self[ChatWallpaperKey.self] }
        set { self[ChatWallpaperKey.self] = newValue }
    }

    /// За лентой своё фото: пузыри подстраивают подложку, как на встроенных обоях.
    var chatHasPhotoWallpaper: Bool {
        get { self[ChatPhotoWallpaperKey.self] }
        set { self[ChatPhotoWallpaperKey.self] = newValue }
    }

    /// За лентой картинка (встроенные обои или своё фото), а не ровный фон.
    var chatWallpaperHasImage: Bool { chatWallpaper.hasImage || chatHasPhotoWallpaper }
}
