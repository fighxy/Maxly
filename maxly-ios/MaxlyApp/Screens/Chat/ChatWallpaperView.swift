import SwiftUI
import UIKit
import MaxlyDomain
import MaxlyUI

/// Картинки обоев из `MaxlyApp/Wallpapers`: JPEG лежат в приложении как есть, без каталога
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

/// Свои фото обоев, прочитанные с диска. Копия уже уменьшена при выборе, поэтому картинка
/// декодируется один раз вне главного потока и дальше рисуется как есть. С размытием берётся
/// размытая копия рядом (`blur-<имя>`): её один раз строит Core Image и кладёт на диск, так что
/// при прокрутке ничего не размывается. В памяти остаются несколько последних.
@MainActor
enum CustomWallpaperImages {
    private static var cache: [URL: UIImage] = [:]
    private static var order: [URL] = []
    private static let limit = 4

    static func key(_ backdrop: CustomWallpaperBackdrop) -> URL { backdrop.blur ? backdrop.blurredURL : backdrop.url }

    static func cached(_ backdrop: CustomWallpaperBackdrop) -> UIImage? { cache[key(backdrop)] }

    static func load(_ backdrop: CustomWallpaperBackdrop) async -> UIImage? {
        let key = key(backdrop)
        if let cached = cache[key] { return cached }
        let base = backdrop.url
        let blurred = backdrop.blur ? backdrop.blurredURL : nil
        let cover = WallpaperPhoto.cover().points
        let decoded = await Task.detached(priority: .userInitiated) { () -> DecodedWallpaper? in
            if let blurred {
                if let image = UIImage(contentsOfFile: blurred.path) {
                    return DecodedWallpaper(image: image.preparingForDisplay() ?? image)
                }
                guard let made = WallpaperPhoto.blurredCopy(of: base, to: blurred, coverPoints: cover) else { return nil }
                return DecodedWallpaper(image: made.preparingForDisplay() ?? made)
            }
            guard let image = UIImage(contentsOfFile: base.path) else { return nil }
            return DecodedWallpaper(image: image.preparingForDisplay() ?? image)
        }.value
        guard let image = decoded?.image else {
            Log.error(.ui, "Своё фото обоев не читается: \(key.lastPathComponent)")
            return nil
        }
        store(image, for: key)
        return image
    }

    static func store(_ image: UIImage, for url: URL) {
        if cache[url] == nil { order.append(url) }
        cache[url] = image
        while order.count > limit {
            cache[order.removeFirst()] = nil
        }
    }
}

/// Декодированная картинка переходит из фоновой задачи только как неизменяемый результат.
private struct DecodedWallpaper: @unchecked Sendable { let image: UIImage }

/// Фон ленты чата: своё фото (чата или общее), иначе встроенные обои из «Оформления»
/// («Без обоев» у чата приходит сюда как `.plain`). Не прокручивается с лентой и не двигается
/// за клавиатурой.
struct ChatWallpaperBackground: View {
    let wallpaper: ChatWallpaper
    /// Своё фото; `nil` — встроенные обои.
    var custom: CustomWallpaperBackdrop? = nil
    /// Уменьшенная картинка: для выбора в «Оформлении».
    var thumbnail = false

    var body: some View {
        if let custom {
            CustomWallpaperLayer(backdrop: custom)
        } else {
            BuiltInWallpaperBackground(wallpaper: wallpaper, thumbnail: thumbnail)
        }
    }
}

/// Своё фото с заполнением по большей стороне и затемнением поверх: два статичных слоя, без
/// размытия на лету. Пока картинка читается, виден ровный фон экрана.
private struct CustomWallpaperLayer: View {
    let backdrop: CustomWallpaperBackdrop
    @State private var loaded: (key: URL, image: UIImage)?

    private var image: UIImage? {
        if let loaded, loaded.key == CustomWallpaperImages.key(backdrop) { return loaded.image }
        return CustomWallpaperImages.cached(backdrop)
    }

    var body: some View {
        Group {
            if let image {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay { Color.black.opacity(backdrop.dimOpacity) }
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                Color.maxlyChatBackground
            }
        }
        .task(id: CustomWallpaperImages.key(backdrop)) {
            guard CustomWallpaperImages.cached(backdrop) == nil else { return }
            let key = CustomWallpaperImages.key(backdrop)
            if let image = await CustomWallpaperImages.load(backdrop) { loaded = (key, image) }
        }
    }
}

/// Встроенные обои с заполнением по большей стороне (без полей, лишнее обрезается) или,
/// без обоев, обычный фон экрана.
struct BuiltInWallpaperBackground: View {
    let wallpaper: ChatWallpaper
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
            Color.maxlyChatBackground
        }
    }
}
