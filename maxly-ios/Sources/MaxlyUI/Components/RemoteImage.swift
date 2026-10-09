import SwiftUI
import ImageIO
import CryptoKit
import MaxlyDomain

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
    private let queue = DispatchQueue(label: "maxly.images.disk", qos: .utility)

    init(directory: URL) {
        self.directory = directory
    }

    static func name(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func file(for url: URL) -> URL {
        directory.appending(path: Self.name(for: url))
    }

    func contains(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: file(for: url).path)
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

/// Загрузка аватаров и фото: готовые пиксели в памяти (`NSCache`), затем свой дисковый кэш,
/// затем сеть. Байты одного адреса загружаются один раз даже для разных размеров декодирования.
///
/// Диск читается и картинка декодируется не на главном потоке: `body` видит только память.
/// На диск ложатся только ответы, которые читаются как картинка: страница ошибки CDN
/// не попадёт в кэш. `URLCache` не используется: он не хранит крупные ответы, слушается
/// заголовков сервера и не даёт посчитать и почистить фото отдельно от остального
/// (docs/storage.md).
public actor ImagePipeline {
    public static let shared = ImagePipeline(directory: defaultDirectory)
    public static let fullSize = 1600

    /// Папка «Фото» стандартной раскладки кэша.
    public static var defaultDirectory: URL? {
        (try? StorageLayout.standard())?.directory(.photos)
    }

    private var session: URLSession
    private nonisolated let memory: ImageMemoryCache
    private nonisolated let disk: ImageDiskCache?
    private var inFlight: [ImageRequest: Task<DecodedImage?, Never>] = [:]
    private var dataInFlight: [URL: Task<Data?, Never>] = [:]
    private var generation = 0
    var pendingImageCount: Int { inFlight.count }
    private let dataLoader: (@Sendable (URL) async -> Data?)?

    /// `directory: nil` — только память (тесты, превью).
    public init(memoryLimit: Int = 300, directory: URL?) {
        session = Self.makeSession()
        memory = ImageMemoryCache(limit: memoryLimit)
        disk = directory.map { ImageDiskCache(directory: $0) }
        dataLoader = nil
    }

    /// Управляемый источник данных для тестов объединения запросов и очистки кэша.
    init(dataLoader: @escaping @Sendable (URL) async -> Data?) {
        session = Self.makeSession()
        memory = ImageMemoryCache(limit: 300)
        disk = nil
        self.dataLoader = dataLoader
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
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
            let disk = url.isFileURL ? nil : disk
            task = Task.detached(priority: .userInitiated) {
                if let loader { return await loader(url) }
                // Файлы записанных фото/кружков URLSession не обязан загружать как HTTP.
                if url.isFileURL { return try? Data(contentsOf: url) }
                if let cached = disk?.data(for: url) { return cached }
                guard let loaded = try? await session.data(from: url),
                      (loaded.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
                if Self.isImage(loaded.0) { disk?.store(loaded.0, for: url) }
                return loaded.0
            }
            dataInFlight[url] = task
        }
        let result = await task.value
        guard generation == started, !task.isCancelled else { return nil }
        // Держим готовые байты до завершения всех декодирований этого URL.
        return result
    }

    /// Скачать картинки заранее (на диск, не декодируя) для ячеек, которые
    /// вот-вот появятся: при показе фото уже не ждёт сети. Уже скачанное пропускается,
    /// одновременно — не больше четырёх загрузок.
    public func prefetch(_ urls: [URL]) async {
        let started = generation
        let wanted = urls.filter { !$0.isFileURL && disk?.contains($0) == false && dataInFlight[$0] == nil }
        guard !wanted.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for url in wanted {
                if running >= 4 {
                    await group.next()
                    running -= 1
                }
                group.addTask { _ = await self.data(for: url, generation: started) }
                running += 1
            }
        }
        // Байты уже на диске: держать их в памяти незачем, если картинку сейчас не декодируют.
        for url in wanted where !inFlight.keys.contains(where: { $0.url == url }) {
            dataInFlight[url] = nil
        }
    }

    /// Байты читаются как картинка: только такие ложатся на диск.
    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Фото стёрты с диска (экран «Данные и память»): забыть и декодированные копии.
    public nonisolated func removeMemory() {
        memory.removeAll()
    }

    /// Выход из аккаунта: чужие аватары и фото не должны остаться ни в памяти, ни на диске,
    /// а старые загрузки не должны заново наполнить кэш другого аккаунта.
    public func removeAll() {
        generation &+= 1
        inFlight.values.forEach { $0.cancel() }
        dataInFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        dataInFlight.removeAll()
        session.invalidateAndCancel()
        session = Self.makeSession()
        memory.removeAll()
        disk?.removeAll()
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
    /// Картинка проявилась полностью: заглушку под ней можно не рисовать.
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(url: URL?, maxPixel: Int = ImagePipeline.fullSize, pipeline: ImagePipeline = .shared, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.pipeline = pipeline
        self.maxPixel = max(16, maxPixel)
        self.placeholder = placeholder()
    }

    /// Картинка из памяти видна сразу, скачанная или прочитанная с диска
    /// проявляется поверх заглушки (размытой миниатюры, букв аватара) за 0,2 с — без
    /// мигания пустым местом. Заглушка остаётся под картинкой, пока та не проявится.
    public var body: some View {
        let image = current
        ZStack {
            if image == nil || !settled {
                placeholder
            }
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: request) {
            guard let request else {
                loaded = nil
                loadedRequest = nil
                settled = false
                return
            }
            if let hit = pipeline.cached(request.url, maxPixel: request.maxPixel) {
                loaded = hit
                loadedRequest = request
                settled = true
                return
            }
            let fresh = loaded == nil
            let image = await pipeline.image(for: request.url, maxPixel: request.maxPixel)
            guard !Task.isCancelled, let image else { return }
            guard fresh, !reduceMotion else {
                // Смена уже показанной картинки (переподписанный адрес) — без движения.
                loaded = image
                loadedRequest = request
                settled = true
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                loaded = image
                loadedRequest = request
            } completion: {
                settled = true
            }
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
