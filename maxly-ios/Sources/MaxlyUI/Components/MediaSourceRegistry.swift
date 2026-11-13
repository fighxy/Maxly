import SwiftUI

/// Где в ленте стоят плитки фото и видео: просмотр вылетает из плитки и возвращается в неё.
///
/// Рамки пишутся при каждом сдвиге ленты, поэтому лежат вне наблюдения: перерисовку вызывает
/// только [hiddenId] — плитка, которая сейчас «в просмотре» и в ленте не видна.
@MainActor
@Observable
public final class MediaSourceRegistry {
    public static let shared = MediaSourceRegistry()

    /// Плитка в координатах окна, адрес её картинки (из кэша `ImagePipeline` с тем же
    /// размером декодирования) и скругление углов.
    public struct Source: Equatable, Sendable {
        public let frame: CGRect
        public let url: URL?
        public let maxPixel: Int
        public let cornerRadius: CGFloat
        /// Скругление каждого угла: у плитки альбома внутренние углы почти прямые, и летящий
        /// кадр начинает с той же формы, что в ленте. Без них — `cornerRadius` у всех углов.
        public let corners: Corners

        public init(frame: CGRect, url: URL?, maxPixel: Int, cornerRadius: CGFloat, corners: Corners? = nil) {
            self.frame = frame
            self.url = url
            self.maxPixel = maxPixel
            self.cornerRadius = cornerRadius
            self.corners = corners ?? Corners(uniform: cornerRadius)
        }
    }

    public struct Corners: Equatable, Sendable {
        public var topLeading: CGFloat
        public var bottomLeading: CGFloat
        public var bottomTrailing: CGFloat
        public var topTrailing: CGFloat

        public init(topLeading: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat, topTrailing: CGFloat) {
            self.topLeading = topLeading
            self.bottomLeading = bottomLeading
            self.bottomTrailing = bottomTrailing
            self.topTrailing = topTrailing
        }

        public init(uniform radius: CGFloat) {
            self.init(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
        }
    }

    @ObservationIgnored private var sources: [String: Source] = [:]
    /// Плитка, открытая в просмотре: в ленте на её месте пусто, пока просмотр не закрылся.
    public var hiddenId: String?

    public init() {}

    public func update(_ id: String, _ source: Source) { sources[id] = source }

    public func remove(_ id: String) { sources[id] = nil }

    public func source(for id: String) -> Source? { sources[id] }
}
