import SwiftUI
import OrbitleDomain

private struct ChatWallpaperKey: EnvironmentKey {
    static let defaultValue: ChatWallpaper = .standard
}

public extension EnvironmentValues {
    /// Обои чата из «Оформления». Корень приложения кладёт сюда выбор, лента рисует их за
    /// пузырями, а пузыри подстраивают подложку.
    var chatWallpaper: ChatWallpaper {
        get { self[ChatWallpaperKey.self] }
        set { self[ChatWallpaperKey.self] = newValue }
    }
}
