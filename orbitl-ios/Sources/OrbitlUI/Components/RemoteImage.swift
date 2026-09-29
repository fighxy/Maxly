import SwiftUI

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
    public init(_ image: PlatformImage) { self.image = image }
}

/// `NSCache` потокобезопасен сам, обёртка только сообщает это компилятору.
final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, DecodedImage>()

    init(limit: Int) { cache.countLimit = limit }

    func object(for url: URL) -> DecodedImage? { cache.object(forKey: url as NSURL) }
    func set(_ image: DecodedImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
    func removeAll() { cache.removeAllObjects() }
}

/// Загрузка аватаров и миниатюр: память (`NSCache`), затем дисковый `URLCache`, затем сеть.
/// Одновременные запросы одного адреса сливаются в один.
public actor ImagePipeline {
    public static let shared = ImagePipeline()

    private let session: URLSession
    private nonisolated let memory: ImageMemoryCache
    private var inFlight: [URL: Task<DecodedImage?, Never>] = [:]

    public init(memoryLimit: Int = 300, diskCapacity: Int = 100 * 1024 * 1024) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: diskCapacity)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory = ImageMemoryCache(limit: memoryLimit)
    }

    /// Уже декодированная картинка, без сети. Нужна, чтобы строка не мигала буквами при прокрутке.
    public nonisolated func cached(_ url: URL) -> DecodedImage? {
        memory.object(for: url)
    }

    public func store(_ image: DecodedImage, for url: URL) {
        memory.set(image, for: url)
    }

    public func image(for url: URL) async -> DecodedImage? {
        if let hit = cached(url) { return hit }
        if let running = inFlight[url] { return await running.value }
        let session = session
        let task = Task<DecodedImage?, Never> {
            guard let loaded = try? await session.data(from: url),
                  (loaded.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = PlatformImage(data: loaded.0) else { return nil }
            return DecodedImage(image)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { memory.set(result, for: url) }
        return result
    }

    /// Выход из аккаунта: чужие аватары не должны остаться в памяти.
    public func removeAll() {
        memory.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// Картинка по адресу. Пока её нет или она не загрузилась, виден `placeholder`.
public struct RemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let pipeline: ImagePipeline
    private let placeholder: Placeholder
    @State private var loaded: DecodedImage?
    @State private var loadedURL: URL?

    public init(url: URL?, pipeline: ImagePipeline = .shared, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.pipeline = pipeline
        self.placeholder = placeholder()
    }

    public var body: some View {
        Group {
            if let image = current {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { return }
            if pipeline.cached(url) != nil { return }
            let image = await pipeline.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                loaded = image
                loadedURL = url
            }
        }
    }

    private var current: Image? {
        guard let url else { return nil }
        let decoded = pipeline.cached(url) ?? (loadedURL == url ? loaded : nil)
        guard let decoded else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: decoded.image)
        #else
        return Image(nsImage: decoded.image)
        #endif
    }
}
