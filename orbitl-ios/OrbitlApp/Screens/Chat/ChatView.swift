import SwiftUI
import OrbitlPresentation
import OrbitlUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var title: String
    /// Модель профиля чата для перехода по нажатию на заголовок.
    var makeProfile: (() -> ChatProfileViewModel?)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let hint = viewModel.emptyHint {
                        VStack(spacing: 12) {
                            OrbitlMark(size: 56)
                                .foregroundStyle(.tertiary)
                            Text(hint)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 80)
                    } else {
                        Button("Раньше") { Task { await viewModel.loadOlder() } }
                            .font(.footnote)
                            .padding(.top, 8)
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, isOutgoing: viewModel.isOutgoing(message)) {
                            Task { await viewModel.retry(id: message.id) }
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, OrbitlTheme.pad)
                .padding(.bottom, 8)
            }
            .onChange(of: viewModel.messages.last?.id) { _, id in
                guard viewModel.stickToBottom, let id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
        // Поле ввода плавает над сообщениями: лента прокручивается под стеклом, а вставка
        // поднимается вместе с клавиатурой.
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        // В открытом чате на iPhone панели вкладок нет: она уезжает при переходе и
        // возвращается при возврате к списку. На iPad список и чат видны вместе, панель остаётся.
        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let makeProfile {
                ToolbarItem(placement: .principal) {
                    NavigationLink {
                        ProfileDestination(make: makeProfile)
                    } label: {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("\(title), открыть профиль")
                }
            }
        }
        .task {
            viewModel.activate()
            await viewModel.loadLatest()
        }
        .onDisappear { viewModel.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            // Приложение уходит в фон: черновик не должен ждать паузы в наборе.
            if phase != .active { viewModel.flushDraft() }
        }
    }

    /// Плавающий пузырь ввода: капсула поля и кнопка отправки на стекле (iOS 26),
    /// на iOS 17–18 — на материале.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .orbitlGlassCapsule()
            }
            OrbitlGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .orbitlGlassCapsule()
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .orbitlProminentButtonStyle()
                    .buttonBorderShape(.circle)
                    .tint(Color.orbitlAccent)
                    .disabled(!viewModel.canSend)
                    .accessibilityLabel("Отправить")
                }
            }
        }
        .padding(.horizontal, OrbitlTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
