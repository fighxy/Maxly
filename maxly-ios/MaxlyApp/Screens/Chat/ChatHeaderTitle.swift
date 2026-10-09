import SwiftUI
import MaxlyPresentation
import MaxlyUI

/// Заголовок чата в панели навигации: название с галочкой и значком
/// «без звука», под ним статус — «в сети» цветом акцента, «печатает» с бегущими точками,
/// число участников или подписчиков серым. Место под статус зарезервировано с первого кадра.
/// Всё — в стеклянной капсуле высотой с круглые «назад» и аватар.
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
                .frame(height: 16)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
        }
        .frame(maxWidth: 220)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .orbitleGlassCapsule()
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .none:
            Color.clear.accessibilityHidden(true)
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
