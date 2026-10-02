import SwiftUI
import OrbitlePresentation
import OrbitleUI

/// Заголовок чата в панели навигации: название с галочкой и значком
/// «без звука», под ним статус — «в сети» цветом акцента, «печатает» с бегущими точками,
/// число участников или подписчиков серым. Смена статуса плавная. Всё — в стеклянной капсуле.
struct ChatHeaderTitle: View {
    let title: String
    let maskedTitle: String
    let status: ChatHeaderStatus
    var isVerified = false
    var isMuted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                PrivateText(title, placeholder: maskedTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.orbitleAccent)
                }
                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            statusLine
                .id(statusKey)
                .transition(.opacity)
        }
        .frame(maxWidth: 230)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
        // Капсула на стекле: той же высоты, что круглые «назад» и аватар.
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .orbitleGlassCapsule()
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .none:
            EmptyView()
        case .plain(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .accent(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.orbitleAccent)
                .lineLimit(1)
        case .typing(let text):
            TypingStatus(text: text)
        }
    }

    /// «печатает» и «в сети» сменяют друг друга растворением, а не перескоком.
    private var statusKey: String {
        switch status {
        case .none: "none"
        case .plain(let text): "plain-" + text
        case .accent(let text): "accent-" + text
        case .typing: "typing"
        }
    }
}
