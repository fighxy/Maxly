import SwiftUI
import UIKit
import OrbitleDomain
import OrbitleUI

/// Картинки обоев из `OrbitleApp/Wallpapers`: JPEG лежат в приложении как есть, без каталога
/// ассетов, чтобы размер сборки был предсказуемым. Раз прочитанная картинка остаётся в памяти.
@MainActor
enum WallpaperImages {
    private static var cache: [String: UIImage] = [:]

    static func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        let url = Bundle.main.url(forResource: name, withExtension: "jpg")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Wallpapers")
        guard let url, let image = UIImage(contentsOfFile: url.path) else {
            Log.error(.ui, "Нет картинки обоев \(name)")
            return nil
        }
        cache[name] = image
        return image
    }
}

/// Фон ленты чата: обои с заполнением по большей стороне (без полей, лишнее обрезается) или,
/// без обоев, обычный фон экрана. Не прокручивается с лентой и не двигается за клавиатурой.
struct ChatWallpaperBackground: View {
    let wallpaper: ChatWallpaper
    /// Уменьшенная картинка: для выбора в «Оформлении».
    var thumbnail = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let name = thumbnail ? wallpaper.thumbnailName(dark: dark) : wallpaper.imageName(dark: dark)
        if let name, let image = WallpaperImages.image(named: name) {
            // Свой размер у картинки не влияет на раскладку: она лишь заполняет место фона.
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .accessibilityHidden(true)
        } else {
            Color.orbitleBackground
        }
    }
}
