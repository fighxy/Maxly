import PhotosUI
import SwiftUI
import MaxlyDomain
import MaxlyPresentation

/// Истории на главном экране: модель в окружении (кольца в списке, шапке и профиле), лента при
/// входе, просмотр на весь экран, выбор файла и экран публикации, короткие сообщения сверху.
struct StoriesHost: ViewModifier {
    let stories: StoriesViewModel?
    @Binding var picking: Bool
    /// Что сделать после первой ленты: свой профиль для плитки «Ваша история».
    var afterStart: @MainActor () async -> Void = {}
    @State private var item: PhotosPickerItem?
    @State private var composing: ComposingStory?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let viewerOpen = stories?.viewer != nil
        return content
            .environment(stories)
            .task {
                guard let stories else { return }
                stories.start()
                await stories.refresh()
                await afterStart()
            }
            .onChange(of: scenePhase) { _, phase in
                // Пуши колец, пока приложение спало, могли потеряться.
                if phase == .active { Task { await stories?.refresh() } }
            }
            .fullScreenCover(isPresented: Binding(get: { viewerOpen }, set: { if !$0 { stories?.close() } })) {
                if let stories { StoryViewerView(stories: stories) }
            }
            .fullScreenCover(item: $composing) { composing in
                StoryComposerView(
                    story: composing.story,
                    onPublish: { audience in
                        self.composing = nil
                        Task { await stories?.publish(composing.story, audience: audience) }
                    },
                    onCancel: { self.composing = nil }
                )
            }
            .photosPicker(isPresented: $picking, selection: $item, matching: .any(of: [.images, .videos]), preferredItemEncoding: .compatible)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                item = nil
                Task {
                    if let story = await StoryFiles.prepare(picked) {
                        composing = ComposingStory(story: story)
                    } else {
                        stories?.message = "Не удалось открыть файл"
                    }
                }
            }
            .overlay(alignment: .top) { StoryBanner(stories: stories) }
    }
}

/// Выбранный файл новой истории для экрана публикации.
struct ComposingStory: Identifiable {
    let id = UUID()
    let story: OutgoingStory
}

/// Короткое сообщение историй сверху («История опубликована», ошибка): гаснет само.
struct StoryBanner: View {
    let stories: StoriesViewModel?

    var body: some View {
        if let text = stories?.message {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { stories?.message = nil }
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2.5))
                    if stories?.message == text { stories?.message = nil }
                }
        }
    }
}
