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

/// Свои фото обоев, прочитанные с диска. Файл уже размером с экран и размыт при сохранении,
/// поэтому картинка декодируется один раз вне главного потока и дальше рисуется как есть.
/// В памяти остаются несколько последних: общие и пара чатов.
@MainActor
enum CustomWallpaperImages {
    private static var cache: [URL: UIImage] = [:]
    private static var order: [URL] = []
    private static let limit = 4

    static func cached(_ url: URL) -> UIImage? { cache[url] }

    static func load(_ url: URL) async -> UIImage? {
        if let cached = cache[url] { return cached }
        let decoded = await Task.detached(priority: .userInitiated) { () -> DecodedWallpaper? in
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return DecodedWallpaper(image: image.preparingForDisplay() ?? image)
        }.value
        guard let image = decoded?.image else {
            Log.error(.ui, "Свои обои не читаются: \(url.lastPathComponent)")
            return nil
        }
        store(image, for: url)
        return image
    }

    /// Только что сохранённая картинка: экран чата покажет её сразу, без чтения с диска.
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

/// Фон ленты чата: своё фото (обои чата или общие), иначе встроенные обои из «Оформления».
/// Не прокручивается с лентой и не двигается за клавиатурой.
struct ChatWallpaperBackground: View {
    let wallpaper: ChatWallpaper
    /// Своё фото; `nil` — встроенные обои.
    var custom: CustomWallpaperBackdrop? = nil
    /// Уменьшенная картинка: для выбора в «Оформлении».
    var thumbnail = false

    var body: some View {
        if let custom {
            CustomWallpaperLayer(backdrop: custom, fallback: wallpaper, thumbnail: thumbnail)
        } else {
            BuiltInWallpaperBackground(wallpaper: wallpaper, thumbnail: thumbnail)
        }
    }
}

/// Своё фото с заполнением по большей стороне и затемнением поверх: два статичных слоя, без
/// размытия на лету. Пока картинка читается с диска, видны встроенные обои.
private struct CustomWallpaperLayer: View {
    let backdrop: CustomWallpaperBackdrop
    let fallback: ChatWallpaper
    let thumbnail: Bool
    @State private var loaded: (url: URL, image: UIImage)?
    @Environment(\.colorScheme) private var colorScheme

    private var image: UIImage? {
        if let loaded, loaded.url == backdrop.url { return loaded.image }
        return CustomWallpaperImages.cached(backdrop.url)
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
                    .overlay { Color.black.opacity(backdrop.dimOpacity(dark: colorScheme == .dark)) }
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                BuiltInWallpaperBackground(wallpaper: fallback, thumbnail: thumbnail)
            }
        }
        .task(id: backdrop.url) {
            guard CustomWallpaperImages.cached(backdrop.url) == nil else { return }
            let url = backdrop.url
            if let image = await CustomWallpaperImages.load(url) { loaded = (url, image) }
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
