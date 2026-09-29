import SwiftUI

public struct AvatarView: View {
    private let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        Text(AvatarInitials.text(for: title))
            .font(.headline)
            .foregroundStyle(Color.orbitlAccent)
            .frame(width: OrbitlTheme.avatar, height: OrbitlTheme.avatar)
            .background(Color.orbitlAccent.opacity(0.16), in: Circle())
            .accessibilityLabel(title)
    }
}
