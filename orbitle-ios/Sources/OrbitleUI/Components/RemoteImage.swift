import SwiftUI
import ImageIO
import CryptoKit
import OrbitleDomain

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Картинка, которую можно передать между потоками. Сама картинка после декодирования не меняется.
public final class DecodedImage: @unchecked Sendable {
    public let image: PlatformImage
    /// Примерный вес в памяти (байты пикселей) для лимита кэша.
    let cost: Int
    public init(_ image: PlatformImage) {
        self.image = image
        #if canImport(UIKit)
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        #else
        let pixels = image.size.width * image.size.height
        #endif
        self.cost = Int(max(pixels, 1) * 4)
    }

    /// Декодирование с уменьшением до `maxPixel` по большей стороне: фото с сервера бывают
    /// в несколько тысяч точек, а в пузыре нужно меньше. Меньше картинка — дольше живёт в кэше.
    static func decode(_ data: Data, maxPixel: Int = 1600) -> DecodedImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnail = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else {
            return PlatformImage(data: data).map(DecodedImage.init)
        }
        #if canImport(UIKit)
        return DecodedImage(UIImage(cgImage: cgImage))
        #else
        return DecodedImage(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        #endif
    }
}

/// `NSCache` потокобезопасен сам, обёртка только сообщает это компилятору.
///
/// Ключ — адрес и размер декодирования: миниатюра строки списка (десятки точек) и то же фото
/// в пузыре хранятся отдельно, и крупные картинки не вытесняют мелкие.
final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, DecodedImage>()

    init(limit: Int, bytes: Int = 160 * 1024 * 1024) {
        cache.countLimit = limit
        cache.totalCostLimit = bytes
    }

    static func key(_ url: URL, _ maxPixel: Int) -> NSString { "\(maxPixel)|\(url.absoluteString)" as NSString }

    func object(for url: URL, maxPixel: Int) -> DecodedImage? { cache.object(forKey: Self.key(url, maxPixel)) }
    func set(_ image: DecodedImage, for url: URL, maxPixel: Int) {
        cache.setObject(image, forKey: Self.key(url, maxPixel), cost: image.cost)
    }
    func removeAll() { cache.removeAllObjects() }
}

/// Скачанные картинки на диске: файл на адрес, имя — SHA-256 адреса.
///
/// Лежат в папке «Фото» кэша (`StorageLayout`), там их считает и чистит экран «Данные и
/// память». Дата изменения файла — время последнего показа: по ней кэш удаляет давно не
/// открытое. Обновляется один раз за запуск, чтобы прокрутка не писала на диск.
final class ImageDiskCache: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private var touched: Set<String> = []
    private let queue = DispatchQueue(label: "orbitle.images.disk", qos: .utility)

    init(directory: URL) {
        self.directory = directory
    }

    static func name(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func file(for url: URL) -> URL {
        directory.appending(path: Self.name(for: url))
    }

    func data(for url: URL) -> Data? {
        let file = file(for: url)
        guard let data = try? Data(contentsOf: file) else { return nil }
        touch(file)
        return data
    }

    func store(_ data: Data, for url: URL) {
        let file = file(for: url)
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            // Папку могли стереть вместе с кэшем: создать и записать ещё раз.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        markTouched(file.lastPathComponent)
    }

    func removeAll() {
        lock.lock()
        touched.removeAll()
        lock.unlock()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @discardableResult
    private func markTouched(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return touched.insert(name).inserted
    }

    private func touch(_ file: URL) {
        guard markTouched(file.lastPathComponent) else { return }
        queue.async {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        }
    }
}

/// Загрузка аватаров и фото: память (`NSCache`), затем свой дисковый кэш, затем сеть.
/// Одновременные запросы одного адреса сливаются в один.
///
/// На диск ложатся только ответы, которые декодировались в картинку: страница ошибки CDN
/// не попадёт в кэш. `URLCache` не используется: он не хранит крупные ответы, слушается
/// заголовков сервера и не даёт посчитать и почистить фото отдельно от остального.
public actor ImagePipeline {
    public static let shared = ImagePipeline(directory: defaultDirectory)

    /// Папка «Фото» стандартной раскладки кэша.
    public static var defaultDirectory: URL? {
        (try? StorageLayout.standard())?.directory(.photos)
    }

    private nonisolated let session: URLSession
    private nonisolated let memory: ImageMemoryCache
    private nonisolated let disk: ImageDiskCache?
    private var inFlight: [NSString: Task<DecodedImage?, Never>] = [:]
    /// Размер декодирования по умолчанию: фото на весь экран.
    public static let fullSize = 1600

    /// `directory: nil` — только память (тесты, превью).
    public init(memoryLimit: Int = 300, directory: URL?) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        memory = ImageMemoryCache(limit: memoryLimit)
        disk = directory.map(ImageDiskCache.init)
    }

    /// Уже декодированная картинка, без сети. Нужна, чтобы строка не мигала буквами при прокрутке.
    public nonisolated func cached(_ url: URL, maxPixel: Int = fullSize) -> DecodedImage? {
        memory.object(for: url, maxPixel: maxPixel)
    }

    /// Картинка, которая уже лежит на диске: файл или своя копия в кэше. Читается сразу,
    /// без ожидания, чтобы при возврате на экран фото не мигали заглушкой. Сеть не трогает.
    public nonisolated func cachedOnDisk(_ url: URL, maxPixel: Int = fullSize) -> DecodedImage? {
        if let hit = memory.object(for: url, maxPixel: maxPixel) { return hit }
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = disk?.data(for: url)
        }
        guard let data, let image = DecodedImage.decode(data, maxPixel: maxPixel) else { return nil }
        memory.set(image, for: url, maxPixel: maxPixel)
        return image
    }

    public func store(_ image: DecodedImage, for url: URL, maxPixel: Int = fullSize) {
        memory.set(image, for: url, maxPixel: maxPixel)
    }

    public func image(for url: URL, maxPixel: Int = fullSize) async -> DecodedImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        let key = ImageMemoryCache.key(url, maxPixel)
        if let running = inFlight[key] { return await running.value }
        let session = session
        let disk = url.isFileURL ? nil : disk
        let task = Task<DecodedImage?, Never>.detached(priority: .userInitiated) {
            if let data = disk?.data(for: url), let image = DecodedImage.decode(data, maxPixel: maxPixel) {
                return image
            }
            guard let loaded = try? await session.data(from: url),
                  (loaded.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = DecodedImage.decode(loaded.0, maxPixel: maxPixel) else { return nil }
            disk?.store(loaded.0, for: url)
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory.set(result, for: url, maxPixel: maxPixel) }
        return result
    }

    /// Фото стёрты с диска (экран «Данные и память»): забыть и декодированные копии.
    public nonisolated func removeMemory() {
        memory.removeAll()
    }

    /// Выход из аккаунта: чужие аватары и фото не должны остаться ни в памяти, ни на диске.
    public func removeAll() {
        memory.removeAll()
        disk?.removeAll()
    }
}

/// Картинка по адресу. Пока её нет или она не загрузилась, виден `placeholder`.
///
/// `maxPixel` — размер декодирования по большей стороне: миниатюре в строке списка хватает
/// сотни точек. Если адрес сменился (сервер переподписал ссылку), прежняя картинка видна,
/// пока не загрузится новая, — строка не мигает заглушкой.
public struct RemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let pipeline: ImagePipeline
    private let maxPixel: Int
    private let placeholder: Placeholder
    @State private var loaded: DecodedImage?
    @State private var loadedURL: URL?

    public init(url: URL?, maxPixel: Int = ImagePipeline.fullSize, pipeline: ImagePipeline = .shared, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.pipeline = pipeline
        self.maxPixel = max(16, maxPixel)
        self.placeholder = placeholder()
    }

    public var body: some View {
        Group {
            if let image = current {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let hit = pipeline.cached(url, maxPixel: maxPixel) {
                if loadedURL != url { loaded = hit; loadedURL = url }
                return
            }
            let image = await pipeline.image(for: url, maxPixel: maxPixel)
            guard !Task.isCancelled, let image else { return }
            let first = loaded == nil
            // Скачанная картинка проявляется поверх заглушки. Из кэша — сразу, иначе при
            // прокрутке всё мигало бы; смена адреса у уже показанной — тоже без анимации.
            if first {
                withAnimation(OrbitleMotion.fade) {
                    loaded = image
                    loadedURL = url
                }
            } else {
                loaded = image
                loadedURL = url
            }
        }
    }

    private var current: Image? {
        guard let url else { return nil }
        let decoded = pipeline.cached(url, maxPixel: maxPixel)
            ?? (loadedURL == url ? loaded : nil)
            ?? pipeline.cachedOnDisk(url, maxPixel: maxPixel)
            ?? loaded
        guard let decoded else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: decoded.image)
        #else
        return Image(nsImage: decoded.image)
        #endif
    }
}
