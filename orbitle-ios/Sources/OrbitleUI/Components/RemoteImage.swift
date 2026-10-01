import SwiftUI
import ImageIO

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

/// Загрузка изображений: готовые пиксели в памяти, затем диск, затем сеть.
/// Данные одного URL загружаются один раз даже для разных размеров декодирования.
public actor ImagePipeline {
    public static let shared = ImagePipeline()
    public static let fullSize = 1600

    private var session: URLSession
    private let diskCapacity: Int
    private nonisolated let memory: ImageMemoryCache
    private var inFlight: [ImageRequest: Task<DecodedImage?, Never>] = [:]
    private var dataInFlight: [URL: Task<Data?, Never>] = [:]
    private var generation = 0
    var pendingImageCount: Int { inFlight.count }
    private let dataLoader: (@Sendable (URL) async -> Data?)?

    public init(memoryLimit: Int = 300, diskCapacity: Int = 100 * 1024 * 1024) {
        self.diskCapacity = diskCapacity
        session = Self.makeSession(diskCapacity: diskCapacity)
        memory = ImageMemoryCache(limit: memoryLimit)
        dataLoader = nil
    }

    /// Управляемый источник данных для тестов объединения запросов и очистки кэша.
    init(dataLoader: @escaping @Sendable (URL) async -> Data?) {
        diskCapacity = 0
        session = Self.makeSession(diskCapacity: 0)
        memory = ImageMemoryCache(limit: 300)
        self.dataLoader = dataLoader
    }

    private static func makeSession(diskCapacity: Int) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: diskCapacity)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }

    /// Только готовые пиксели: безопасно вызывать из body, без чтения диска и decode.
    public nonisolated func cached(_ url: URL, maxPixel: Int = fullSize) -> DecodedImage? {
        memory.object(for: url, maxPixel: max(16, maxPixel))
    }

    public func store(_ image: DecodedImage, for url: URL, maxPixel: Int = fullSize) {
        memory.set(image, for: url, maxPixel: max(16, maxPixel))
    }

    public func image(for url: URL, maxPixel: Int = fullSize) async -> DecodedImage? {
        let request = ImageRequest(url: url, maxPixel: max(16, maxPixel))
        if let hit = cached(url, maxPixel: request.maxPixel) { return hit }
        let started = generation
        let task: Task<DecodedImage?, Never>
        if let running = inFlight[request] {
            task = running
        } else {
            task = Task.detached(priority: .userInitiated) { [self] in
                guard let data = await data(for: url, generation: started), !Task.isCancelled else { return nil }
                let decoded = DecodedImage.decode(data, maxPixel: request.maxPixel)
                return Task.isCancelled ? nil : decoded
            }
            inFlight[request] = task
        }
        let result = await task.value
        // Очистка могла запустить новый запрос с тем же ключом: старый его не трогает.
        guard generation == started, !task.isCancelled else { return nil }
        inFlight[request] = nil
        if !inFlight.keys.contains(where: { $0.url == url }) { dataInFlight[url] = nil }
        if let result { memory.set(result, for: url, maxPixel: request.maxPixel) }
        return result
    }

    private func data(for url: URL, generation started: Int) async -> Data? {
        guard generation == started else { return nil }
        let task: Task<Data?, Never>
        if let running = dataInFlight[url] {
            task = running
        } else {
            let session = session
            let loader = dataLoader
            task = Task.detached(priority: .userInitiated) {
                if let loader { return await loader(url) }
                // Файлы записанных фото/кружков URLSession не обязан загружать как HTTP.
                if url.isFileURL { return try? Data(contentsOf: url) }
                if let cached = session.configuration.urlCache?.cachedResponse(for: URLRequest(url: url)) {
                    return cached.data
                }
                guard let loaded = try? await session.data(from: url),
                      (loaded.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
                return loaded.0
            }
            dataInFlight[url] = task
        }
        let result = await task.value
        guard generation == started, !task.isCancelled else { return nil }
        // Держим готовые байты до завершения всех декодирований этого URL.
        return result
    }

    /// Выход: старые загрузки не должны заново наполнить кэш другого аккаунта.
    public func removeAll() {
        generation &+= 1
        inFlight.values.forEach { $0.cancel() }
        dataInFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        dataInFlight.removeAll()
        session.invalidateAndCancel()
        session.configuration.urlCache?.removeAllCachedResponses()
        session = Self.makeSession(diskCapacity: diskCapacity)
        memory.removeAll()
    }
}

/// Identity включает размер: смена размера плитки должна запросить новые пиксели.
struct ImageRequest: Hashable, Sendable {
    let url: URL
    let maxPixel: Int
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
    @State private var loadedRequest: ImageRequest?

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
        .task(id: request) {
            guard let request else { loaded = nil; loadedRequest = nil; return }
            let image: DecodedImage?
            if let hit = pipeline.cached(request.url, maxPixel: request.maxPixel) {
                image = hit
            } else {
                image = await pipeline.image(for: request.url, maxPixel: request.maxPixel)
            }
            guard !Task.isCancelled, let image else { return }
            // Смена готовых пикселей не анимирует размер всей строки/ленты.
            loaded = image
            loadedRequest = request
        }
    }

    private var request: ImageRequest? {
        url.map { ImageRequest(url: $0, maxPixel: maxPixel) }
    }

    private var current: Image? {
        guard let url else { return nil }
        let decoded = pipeline.cached(url, maxPixel: maxPixel)
            ?? (loadedRequest?.url == url ? loaded : nil)
            ?? loaded
        guard let decoded else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: decoded.image)
        #else
        return Image(nsImage: decoded.image)
        #endif
    }
}
