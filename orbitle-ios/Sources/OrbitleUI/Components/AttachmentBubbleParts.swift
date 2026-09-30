import SwiftUI
import OrbitleDomain

/// Кольцо загрузки поверх пузыря своего сообщения с крестиком отмены.
struct UploadRing: View {
    let progress: Double
    let onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.45))
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 3)
                .padding(5)
            Circle()
                .trim(from: 0, to: max(0.03, min(progress, 1)))
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(5)
                .animation(.linear(duration: 0.2), value: progress)
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отменить отправку")
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(Int((progress * 100).rounded())) %")
    }
}

/// Карточка контакта в пузыре: аватар или инициалы, имя и номер.
struct ContactCardRow: View {
    let contact: ContactContent
    let outgoing: Bool

    var body: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name.isEmpty ? "Контакт" : contact.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(outgoing ? Color.white : Color.primary)
                if !contact.phone.isEmpty {
                    Text(contact.phone)
                        .font(.caption)
                        .foregroundStyle(outgoing ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Контакт \(contact.name)")
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = contact.avatarURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initials
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        let letters = contact.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return ZStack {
            Circle().fill(outgoing ? Color.white.opacity(0.22) : Color.orbitleAccent)
            if letters.isEmpty {
                Image(systemName: "person.fill").foregroundStyle(.white)
            } else {
                Text(letters.uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}
