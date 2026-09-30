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
    var cornerRadius: CGFloat = 12
    var loadingId: String?
    /// Одиночный кадр занимает всю ширину (пузырь с подписью не должен быть шире фото).
    var fillsWidth = false
    let onOpen: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let visuals = attachments.filter(\.isVisual)
        let round = visuals.count == 1 && visuals[0].video?.isRound == true
        let layout = fillsWidth && visuals.count == 1 && !round
            ? ChatContentFormat.fullWidthTile(aspect: aspect(visuals[0]), width: Double(maxWidth))
            : ChatContentFormat.album(aspects: visuals.map(aspect), maxWidth: Double(round ? min(maxWidth, Self.roundSide) : maxWidth))
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: layout.width, height: layout.height)
            ForEach(Array(visuals.enumerated()), id: \.element.id) { index, item in
                if let tile = layout.tiles.first(where: { $0.index == index }) {
                    cell(item, tile: tile)
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
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
            if item.video != nil {
                videoBadge(loading: loadingId == item.id)
            } else if loadingId == item.id {
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .overlay(alignment: .topLeading) {
            if let video = item.video, video.durationMs > 0 {
                overlayCapsule(ChatContentFormat.clock(ms: video.durationMs))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if tile.corners.bottomRight, let time {
                timeCapsule(time)
            }
        }
        .frame(width: width, height: height)
        .clipShape(mask(round: round, corners: tile.corners))
        .contentShape(mask(round: round, corners: tile.corners))
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
        if let data = item.photo?.preview ?? item.video?.preview, let image = PlatformImage(data: data) {
            #if canImport(UIKit)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 8)
            #else
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 8)
            #endif
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
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
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

    /// Диаметр кружка в ленте: не во всю ширину.
    static let roundSide: CGFloat = 220

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
