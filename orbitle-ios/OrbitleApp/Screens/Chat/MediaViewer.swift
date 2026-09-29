import AVKit
import SwiftUI
import UIKit
import OrbitlePresentation

struct MediaViewer: View {
    let request: MediaViewerRequest
    let onClose: () -> Void
    @State private var selection: String

    init(request: MediaViewerRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
        _selection = State(initialValue: request.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(request.slides) { slide in
                    page(slide)
                        .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: request.slides.count > 1 ? .automatic : .never))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Закрыть")
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 120 { onClose() }
            }
        )
    }

    @ViewBuilder
    private func page(_ slide: MediaSlide) -> some View {
        if slide.isVideo, let url = slide.playURL {
            PlayerPage(url: url)
        } else {
            AsyncImage(url: slide.stillURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Color.clear
                }
            }
        }
    }
}

/// Плеер не меняет адрес после старта: подмена файла из кэша не должна перезапускать ролик.
private struct PlayerPage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
