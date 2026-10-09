import SwiftUI
import AVKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// «Мои истории» (docs/stories-archive.md): архив своих историй сеткой в три колонки, новые
/// сверху. Дойдя до последней плитки, экран просит следующую страницу. Нажатие открывает
/// историю на весь экран.
struct StoryArchiveView: View {
    let model: StoryArchiveModel
    @State private var opened: Story?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        content
            .navigationTitle("Мои истории")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.activate() }
            .fullScreenCover(item: $opened) { story in
                ArchivedStoryView(story: story) { opened = nil }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView {
                Label(StoryArchiveModel.emptyTitle, systemImage: "photo.stack")
            } description: {
                Text(StoryArchiveModel.emptyText)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Не получилось", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") { Task { await model.reload() } }
            }
        case .ready:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(model.stories) { story in
                    Button {
                        if story.media != nil { opened = story }
                    } label: {
                        ArchiveTile(story: story)
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.canLoadMore {
                Group {
                    if let error = model.pageError {
                        Button("Повторить") { Task { await model.loadMore() } }
                            .accessibilityHint(error)
                    } else {
                        ProgressView()
                            .task(id: model.stories.count) { await model.loadMore() }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .refreshable { await model.reload() }
    }
}

/// Плитка архива: обложка, дата и значок видео.
private struct ArchiveTile: View {
    let story: Story

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: cover, maxPixel: 480) {
                    Image(systemName: story.media == nil ? "eye.slash" : "photo")
                        .foregroundStyle(.secondary)
                }
                .scaledToFill()
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if story.media?.isVideo == true {
                        Image(systemName: "play.fill")
                    }
                    Text(story.time.formatted(.dateTime.day().month(.abbreviated)))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(6)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var cover: URL? {
        guard let media = story.media else { return nil }
        return media.isVideo ? media.thumbnailURL : media.url
    }

    private var accessibilityText: String {
        let kind = story.media?.isVideo == true ? "Видео" : "Фото"
        return "\(kind), \(story.time.formatted(date: .long, time: .shortened))"
    }
}

/// История из архива на весь экран: фото или видео со звуком.
private struct ArchivedStoryView: View {
    let story: Story
    let onClose: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let media = story.media {
                if media.isVideo {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .onAppear {
                            let next = AVPlayer(url: media.url)
                            player = next
                            next.play()
                        }
                        .onDisappear { player?.pause() }
                } else {
                    AsyncImage(url: media.url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Закрыть")
            .padding(.trailing, 8)
        }
    }
}
