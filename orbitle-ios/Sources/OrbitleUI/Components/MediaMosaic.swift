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
        if visuals.count == 1, let only = visuals.first {
            cell(only, size: singleSize(only))
        } else if !visuals.isEmpty {
            let side = max(72, (maxWidth - 4) / 2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
                ForEach(visuals, id: \.id) { item in
                    cell(item, size: CGSize(width: side, height: side))
                }
            }
            .frame(width: maxWidth)
        }
    }

    private func singleSize(_ item: ChatAttachment) -> CGSize {
        let pixels = item.photo.map { ($0.width, $0.height) } ?? item.video.map { ($0.width, $0.height) } ?? (nil, nil)
        let frame = ChatContentFormat.frame(
            pixelWidth: pixels.0,
            pixelHeight: pixels.1,
            maxWidth: Double(maxWidth)
        )
        return CGSize(width: frame.width, height: frame.height)
    }

    private func cell(_ item: ChatAttachment, size: CGSize) -> some View {
        let round = item.video?.isRound == true
        return Button {
            onOpen(item.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: still(item)) {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: size.width, height: size.height)
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
                } else if let time {
                    Text(time)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
        }
        .buttonStyle(.plain)
    }

    private func still(_ item: ChatAttachment) -> URL? {
        item.photo?.displayURL ?? item.video?.displayURL
    }
}
