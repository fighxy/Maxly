import SwiftUI
import Lottie

/// Lottie-анимации Max (стикеры и анимодзи) по адресу: память, диск (`Caches/Lottie`), сеть.
/// Повторные запросы одного адреса ждут одну загрузку. JSON разбирается вне главного потока.
public final class LottieStore: @unchecked Sendable {
    public static let shared = LottieStore()

    private let lock = NSLock()
    private var memory: [URL: LottieAnimation] = [:]
    private var order: [URL] = []
    private var inflight: [URL: Task<LottieAnimation?, Never>] = [:]
    private let directory: URL?
    private let memoryLimit: Int

    public init(memoryLimit: Int = 160, directory: URL? = LottieStore.standardDirectory()) {
        self.memoryLimit = memoryLimit
        self.directory = directory
    }

    public static func standardDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lottie", isDirectory: true)
    }

    /// Уже разобранная анимация: видна сразу, без заглушки.
    public func cached(_ url: URL) -> LottieAnimation? {
        lock.withLock { memory[url] }
    }

    public func animation(for url: URL) async -> LottieAnimation? {
        if let hit = cached(url) { return hit }
        let task: Task<LottieAnimation?, Never> = lock.withLock {
            if let running = inflight[url] { return running }
            let directory = directory
            let running = Task.detached(priority: .userInitiated) { () -> LottieAnimation? in
                await Self.load(url, directory: directory)
            }
            inflight[url] = running
            return running
        }
        let animation = await task.value
        lock.withLock {
            inflight[url] = nil
            if let animation { remember(animation, for: url) }
        }
        return animation
    }

    /// Очистка кэша («Данные и память», выход из аккаунта).
    public func removeAll() {
        lock.withLock {
            memory = [:]
            order = []
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func remember(_ animation: LottieAnimation, for url: URL) {
        if memory[url] == nil { order.append(url) }
        memory[url] = animation
        while order.count > memoryLimit {
            memory[order.removeFirst()] = nil
        }
    }

    private static func load(_ url: URL, directory: URL?) async -> LottieAnimation? {
        let file = directory?.appendingPathComponent(fileName(url))
        if let file, let data = try? Data(contentsOf: file), let animation = decode(data) {
            return animation
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let animation = decode(data) else { return nil }
        if let file, let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return animation
    }

    /// Обычный JSON или он же в gzip (как `.tgs`).
    static func decode(_ data: Data) -> LottieAnimation? {
        let json = gunzip(data) ?? data
        return try? LottieAnimation.from(data: json)
    }

    /// gzip → DEFLATE без заголовка → `zlib` Foundation. `nil`, если это не gzip.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0, index + 2 <= bytes.count {
            index += 2 + Int(bytes[index]) + Int(bytes[index + 1]) << 8
        }
        if flags & 0x08 != 0 { while index < bytes.count, bytes[index] != 0 { index += 1 }; index += 1 }
        if flags & 0x10 != 0 { while index < bytes.count, bytes[index] != 0 { index += 1 }; index += 1 }
        if flags & 0x02 != 0 { index += 2 }
        guard index < bytes.count - 8 else { return nil }
        let deflate = Data(bytes[index..<(bytes.count - 8)])
        return try? (deflate as NSData).decompressed(using: .zlib) as Data
    }

    /// Устойчивое имя файла по адресу (FNV-1a), без запрещённых символов.
    static func fileName(_ url: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.absoluteString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16) + ".json"
    }
}

/// Стикер или анимодзи: Lottie, если есть, иначе картинка; пока Lottie грузится — картинка
/// (или эмодзи). С Reduce Motion и `playing == false` стоит первый кадр.
public struct AnimatedSticker<Placeholder: View>: View {
    private let lottieURL: URL?
    private let stillURL: URL?
    private let size: CGFloat
    private let playing: Bool
    private let placeholder: Placeholder
    private let store: LottieStore
    @State private var animation: LottieAnimation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        lottieURL: URL?,
        stillURL: URL?,
        size: CGFloat,
        playing: Bool = true,
        store: LottieStore = .shared,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.lottieURL = lottieURL
        self.stillURL = stillURL
        self.size = size
        self.playing = playing
        self.store = store
        self.placeholder = placeholder()
        _animation = State(initialValue: lottieURL.flatMap { store.cached($0) })
    }

    public var body: some View {
        ZStack {
            if let animation {
                LottieView(animation: animation)
                    .resizable()
                    .playbackMode(playing && !reduceMotion
                        ? .playing(.toProgress(1, loopMode: .loop))
                        : .paused(at: .progress(0)))
                    .transition(.opacity)
            } else if stillURL != nil {
                RemoteImage(url: stillURL, maxPixel: Int(size * 3)) { placeholder }
                    .clipped()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: lottieURL) {
            guard let lottieURL else {
                animation = nil
                return
            }
            if let hit = store.cached(lottieURL) {
                animation = hit
                return
            }
            let loaded = await store.animation(for: lottieURL)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { animation = loaded }
        }
    }
}

public extension AnimatedSticker where Placeholder == Color {
    init(lottieURL: URL?, stillURL: URL?, size: CGFloat, playing: Bool = true) {
        self.init(lottieURL: lottieURL, stillURL: stillURL, size: size, playing: playing) { Color.clear }
    }
}
