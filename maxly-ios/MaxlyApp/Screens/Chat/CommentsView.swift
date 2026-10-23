import SwiftUI
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

/// Комментарии поста канала в модальном окне: сверху пост, под ним обсуждение с авторами,
/// внизу поле ввода. Кнопка «Закрыть» в навигационной панели.
/// В приватном режиме пост и комментарии закрыты, как пузыри чата, и открываются касанием.
///
/// Лента — тот же UICollectionView-движок, что у чата: старое сверху, новое снизу.
struct CommentsView: View {
    @Bindable var model: CommentsViewModel
    let onClose: () -> Void
    /// Блок автора комментария. Ошибку показывает этот экран.
    var onBlockAuthor: ((Message) async throws -> Void)? = nil
    @State private var blockNotice: String?
    @State private var reveal = PrivateModeReveal()
    @State private var atBottom = true
    /// Верх поля ввода в глобальных координатах. `0` — ещё не измерен.
    @State private var composerTop: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.privateMode) private var privateMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Окружение пузырей для ячеек ленты: через границу UIKit оно само не проходит.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.imageURLSizing) private var imageURLSizing
    @Environment(\.gifAutoplay) private var gifAutoplay

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                CommentsCollectionFeed(
                    model: model,
                    width: geo.size.width,
                    reveal: reveal,
                    reduceMotion: reduceMotion,
                    atBottom: $atBottom,
                    composerTop: composerTop > 0 ? composerTop : nil,
                    environment: FeedEnvironment(
                        privateMode: privateMode,
                        dynamicTypeSize: dynamicTypeSize,
                        imageURLSizing: imageURLSizing,
                        gifAutoplay: gifAutoplay
                    ),
                    onBlockAuthor: onBlockAuthor,
                    onBlockNotice: { blockNotice = $0 }
                )
                // Под стеклом шапки и поля ввода, как лента чата: края не срезают комментарии.
                .ignoresSafeArea(.container, edges: .vertical)
                .refreshable { await model.reload() }
            }
            .background(Color.maxlyChatBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть", action: onClose)
                }
            }
            .task { await model.load() }
            .onDisappear { reveal.hideAll() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { reveal.hideAll() }
            }
            .onChange(of: privateMode) { _, _ in reveal.hideAll() }
            .alert("Комментарий", isPresented: Binding(get: { blockNotice != nil }, set: { if !$0 { blockNotice = nil } })) {
                Button("OK", role: .cancel) { blockNotice = nil }
            } message: {
                Text(blockNotice ?? "")
            }
        }
    }

    // MARK: Ввод

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.app(.caption))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .maxlyGlassCapsule()
            }
            MaxlyGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Комментарий", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .maxlyGlassRounded(radius: 22)
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .maxlyProminentButtonStyle()
                    .buttonBorderShape(.circle)
                    .tint(Color.maxlyAccent)
                    .disabled(!model.canSend)
                    .accessibilityLabel("Отправить комментарий")
                }
            }
        }
        .padding(.horizontal, MaxlyTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { composerTop = $0 }
    }
}
