import AVKit
import SwiftUI
import UIKit
import MaxlyDomain

/// Новая история: предпросмотр выбранного файла, кому показать и «Опубликовать». История живёт сутки.
struct StoryComposerView: View {
    let story: OutgoingStory
    let onPublish: (StoryAudience) -> Void
    let onCancel: () -> Void
    @State private var audience: StoryAudience = .everyone
    @State private var player: AVPlayer?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            preview
            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Отмена")
                    Text("Новая история").font(.headline)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                Spacer()
                VStack(spacing: 12) {
                    Text("Кто увидит")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                    Picker("Кто увидит", selection: $audience) {
                        Text("Все").tag(StoryAudience.everyone)
                        Text("Контакты").tag(StoryAudience.contacts)
                    }
                    .pickerStyle(.segmented)
                    Button {
                        player?.pause()
                        onPublish(audience)
                    } label: {
                        Text("Опубликовать на сутки")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
            }
        }
        .onAppear {
            if !story.isVideo, image == nil { image = UIImage(contentsOfFile: story.fileURL.path) }
            guard story.isVideo, player == nil else { return }
            let preview = AVPlayer(url: story.fileURL)
            preview.isMuted = true
            preview.play()
            player = preview
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var preview: some View {
        if story.isVideo {
            if let player {
                VideoPlayer(player: player)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
    }
}
