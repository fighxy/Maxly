import SwiftUI
import OrbitleDomain
import OrbitlePresentation

/// Фото и видео сообщения: одно во всю ширину или альбом рядами (`ChatContentFormat.album`).
///
/// Пока грузится картинка, видна размытая миниатюра из самого вложения. На видео — кнопка
/// воспроизведения и длительность, на последней плитке сообщения без текста — время.
struct MediaMosaic: View {
    let attachments: [ChatAttachment]
    let maxWidth: CGFloat
    let time: String?
    var status: MessageStatus?
    /// Своё прочитано: две галочки.
    var isRead = false
    var cornerRadius: CGFloat = 12
    var loadingId: String?
    /// Одиночный кадр занимает всю ширину (пузырь с подписью не должен быть шире фото).
    var fillsWidth = false
    /// Играющий в ленте кружок (плеер от приложения): рисуется в круге поверх обложки,
    /// а сам круг на время воспроизведения крупнее, как в Telegram.
    var roundPlayer: AnyView?
    let onOpen: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let visuals = attachments.filter(\.isVisual)
        let round = visuals.count == 1 && visuals[0].video?.isRound == true
        let layout = fillsWidth && visuals.count == 1 && !round
            ? ChatContentFormat.fullWidthTile(aspect: aspect(visuals[0]), width: Double(maxWidth))
            : ChatContentFormat.album(aspects: visuals.map(aspect), maxWidth: Double(round ? min(maxWidth, roundPlayer == nil ? Self.roundSide : Self.playingRoundSide) : maxWidth))
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: layout.width, height: layout.height)
            ForEach(Array(visuals.enumerated()), id: \.element.id) { index, item in
                if let tile = layout.tiles.first(where: { $0.index == index }) {
                    cell(item, tile: tile)
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: roundPlayer == nil)
    }

    private func aspect(_ item: ChatAttachment) -> Double {
        if item.video?.isRound == true { return 1 }
        let pixels = item.photo.map { ($0.width, $0.height) } ?? item.video.map { ($0.width, $0.height) }
        guard let width = pixels?.0, let height = pixels?.1, width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }

    private func cell(_ item: ChatAttachment, tile: AlbumTile) -> some View {
        let round = item.video?.isRound == true
        let width = CGFloat(tile.width)
        let height = CGFloat(tile.height)
        // Не `Button`: кнопка ловит касание в начале прокрутки и подсвечивается, а жест
        // касания срабатывает только на короткое нажатие без движения.
        return ZStack {
            RemoteImage(url: still(item), maxPixel: Self.decodeSize(width: width, height: height)) {
                placeholder(item)
            }
            .frame(width: width, height: height)
            .clipped()
            if round, let roundPlayer {
                roundPlayer
                    .frame(width: width, height: height)
            } else if item.video != nil {
                videoBadge(loading: loadingId == item.id)
            } else if loadingId == item.id {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .frame(width: width, height: height)
        .clipShape(mask(round: round, corners: tile.corners))
        .contentShape(mask(round: round, corners: tile.corners))
        // Подписи поверх маски: у кружка углы квадрата вне круга, и маска их срезала бы.
        .overlay(alignment: round ? .bottomLeading : .topLeading) {
            if let video = item.video, video.durationMs > 0, !(round && roundPlayer != nil) {
                overlayCapsule(ChatContentFormat.clock(ms: video.durationMs))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if tile.corners.bottomRight, let time {
                timeCapsule(time)
            }
        }
        .onTapGesture { onOpen(item.id) }
        .frame(width: width, height: height, alignment: .center)
        .offset(x: CGFloat(tile.x), y: CGFloat(tile.y))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.video == nil ? "Фото" : "Видео")
        .accessibilityAction { onOpen(item.id) }
    }

    @ViewBuilder
    private func placeholder(_ item: ChatAttachment) -> some View {
        if let data = item.photo?.preview ?? item.video?.preview {
            AttachmentPreview(data: data)
        } else {
            Color.secondary.opacity(0.18)
        }
    }

    private func videoBadge(loading: Bool) -> some View {
        ZStack {
            Circle().fill(.black.opacity(0.45))
            if loading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 2)
            }
        }
        .frame(width: 48, height: 48)
    }

    private func overlayCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white)
            .padding(6)
    }

    private func timeCapsule(_ time: String) -> some View {
        HStack(spacing: 3) {
            Text(time)
                .font(.caption2.monospacedDigit().weight(.medium))
            switch status {
            case .sending:
                Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
            case .sent:
                DeliveryChecks(read: isRead, lineWidth: 1.3)
                    .scaleEffect(0.85)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10, weight: .semibold))
            case nil:
                EmptyView()
            }
        }
        .animation(OrbitleMotion.quick(reduceMotion: reduceMotion), value: status)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.black.opacity(0.45), in: Capsule())
        .foregroundStyle(.white)
        .padding(6)
    }

    private func mask(round: Bool, corners: AlbumCorners) -> AnyShape {
        if round { return AnyShape(Circle()) }
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: corners.topLeft ? cornerRadius : 2,
            bottomLeadingRadius: corners.bottomLeft ? cornerRadius : 2,
            bottomTrailingRadius: corners.bottomRight ? cornerRadius : 2,
            topTrailingRadius: corners.topRight ? cornerRadius : 2,
            style: .continuous
        ))
    }

    /// Диаметр кружка в ленте, как в Telegram: не во всю ширину.
    static let roundSide: CGFloat = 220
    /// Диаметр играющего кружка.
    static let playingRoundSide: CGFloat = 300

    /// Размер декодирования плитки: сторона в точках ×3, ступенями по 256, чтобы соседние
    /// размеры одного фото делили кэш.
    static func decodeSize(width: CGFloat, height: CGFloat) -> Int {
        let pixels = Int((max(width, height) * 3).rounded(.up))
        return min(ImagePipeline.fullSize, max(256, (pixels + 255) / 256 * 256))
    }

    private func still(_ item: ChatAttachment) -> URL? {
        item.photo?.displayURL ?? item.video?.displayURL
    }
}

/// Даже маленькое preview декодируется вне body, один раз на значение Data.
private struct AttachmentPreview: View {
    let data: Data
    @State private var decoded: DecodedImage?

    init(data: Data) {
        self.data = data
        // Уже декодированная миниатюра видна сразу: при прокрутке назад пузырь не мигает серым.
        _decoded = State(initialValue: PreviewCache.shared.object(forKey: data as NSData))
    }

    var body: some View {
        Group {
            if let decoded {
                #if canImport(UIKit)
                Image(uiImage: decoded.image).resizable().scaledToFill().blur(radius: 8)
                #else
                Image(nsImage: decoded.image).resizable().scaledToFill().blur(radius: 8)
                #endif
            } else {
                Color.secondary.opacity(0.18)
            }
        }
        .task(id: data) {
            if let hit = PreviewCache.shared.object(forKey: data as NSData) {
                decoded = hit
                return
            }
            let bytes = data
            let task = Task.detached(priority: .userInitiated) { DecodedImage.decode(bytes, maxPixel: 256) }
            let image = await task.value
            guard !Task.isCancelled, let image else { return }
            PreviewCache.shared.setObject(image, forKey: bytes as NSData)
            decoded = image
        }
    }
}

/// Декодированные миниатюры вложений (несколько сотен байт WebP каждая): `NSCache`
/// потокобезопасен сам, обёртка только сообщает это компилятору.
private final class PreviewCache: @unchecked Sendable {
    static let shared = PreviewCache()
    private let cache: NSCache<NSData, DecodedImage> = {
        let cache = NSCache<NSData, DecodedImage>()
        cache.countLimit = 300
        return cache
    }()

    func object(forKey key: NSData) -> DecodedImage? { cache.object(forKey: key) }
    func setObject(_ image: DecodedImage, forKey key: NSData) { cache.setObject(image, forKey: key) }
}
