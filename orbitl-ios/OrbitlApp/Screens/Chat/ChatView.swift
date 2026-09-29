import SwiftUI
import OrbitlUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Button("Раньше") { Task { await viewModel.loadOlder() } }
                            .font(.footnote)
                            .padding(.top, 8)
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message, isOutgoing: message.authorId == viewModel.currentUserId) {
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
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OrbitlTheme.pad)
            }
            composer
        }
        .navigationTitle("Чат")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.activate()
            await viewModel.loadLatest()
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
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(OrbitlTheme.pad)
        .background(.bar)
    }
}
