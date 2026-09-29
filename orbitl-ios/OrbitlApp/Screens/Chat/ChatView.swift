import SwiftUI
import OrbitlPresentation
import OrbitlUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var title: String
    /// Модель профиля чата для перехода по нажатию на заголовок.
    var makeProfile: (() -> ChatProfileViewModel?)?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
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
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OrbitlTheme.pad)
            }
            composer
        }
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.orbitlIncoming, in: RoundedRectangle(cornerRadius: OrbitlTheme.radius))
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.orbitlAccent)
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Отправить")
        }
        .padding(OrbitlTheme.pad)
        .background(.bar)
    }
}
