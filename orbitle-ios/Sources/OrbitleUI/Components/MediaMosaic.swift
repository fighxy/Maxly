import SwiftUI
import OrbitleDomain
import OrbitlePresentation

struct MediaMosaic: View {
    let attachments: [ChatAttachment]
    let maxWidth: CGFloat
    let time: String?
    let onOpen: (String) -> Void

    var body: some View {
        let visuals = attachments.filter(\.isVisual)
        let layout = ChatContentFormat.album(aspects: visuals.map(aspect), maxWidth: Double(maxWidth))
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: layout.width, height: layout.height)
            ForEach(Array(visuals.enumerated()), id: \.element.id) { index, item in
                if let tile = layout.tiles.first(where: { $0.index == index }) {
                    cell(item, tile: tile, clock: time)
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

    private func cell(_ item: ChatAttachment, tile: AlbumTile, clock: String?) -> some View {
        let round = item.video?.isRound == true
        let width = CGFloat(tile.width)
        let height = CGFloat(tile.height)
        return Button {
            onOpen(item.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: still(item)) {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: width, height: height)
                .clipped()
                if item.video != nil {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let video = item.video, video.durationMs > 0 {
                        Text(ChatContentFormat.clock(ms: video.durationMs))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.45), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                } else if tile.corners.bottomRight, let clock {
                    Text(clock)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .frame(width: width, height: height)
            .clipShape(mask(round: round, corners: tile.corners))
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height, alignment: .center)
        .offset(x: CGFloat(tile.x), y: CGFloat(tile.y))
        .accessibilityLabel(item.video == nil ? "Фото" : "Видео")
    }

    private func mask(round: Bool, corners: AlbumCorners) -> AnyShape {
        if round { return AnyShape(Circle()) }
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: corners.topLeft ? 12 : 0,
            bottomLeadingRadius: corners.bottomLeft ? 12 : 0,
            bottomTrailingRadius: corners.bottomRight ? 12 : 0,
            topTrailingRadius: corners.topRight ? 12 : 0,
            style: .continuous
        ))
    }

    private func still(_ item: ChatAttachment) -> URL? {
        item.photo?.displayURL ?? item.video?.displayURL
    }
}
