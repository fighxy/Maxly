import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

struct CommentsView: View {
    @Bindable var model: CommentsViewModel
    var currentUserId: String
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollViewReader { _ in
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let empty = model.emptyText {
                            Text(empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        }
                        ForEach(model.comments) { message in
                            MessageBubble(
                                message: message,
                                isOutgoing: model.isOutgoing(message, currentUserId: currentUserId),
                                maxWidth: geo.size.width * OrbitleTheme.bubbleMax
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, OrbitleTheme.pad)
                    .padding(.vertical, 8)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.activate() }
        .onDisappear { model.deactivate() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
            OrbitleGlassGroup(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Комментарий", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .orbitleGlassCapsule()
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .orbitleProminentButtonStyle()
                    .buttonBorderShape(.circle)
                    .tint(Color.orbitleAccent)
                    .disabled(!model.canSend)
                    .accessibilityLabel("Отправить комментарий")
                }
            }
        }
        .padding(.horizontal, OrbitleTheme.pad)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
