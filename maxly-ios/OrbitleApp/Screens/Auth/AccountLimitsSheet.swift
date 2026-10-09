import SwiftUI
import OrbitleDomain
import OrbitlePresentation
import OrbitleUI

/// Выезжающая панель с ограничениями аккаунта.
///
/// Всплывает на главном экране после входа по коду или паролю и после регистрации, а из
/// «Настроек» открывается, пока ограничения входа действуют. Тексты готовит `AccountLimitsText`.
struct AccountLimitsSheet: View {
    let content: AccountLimitsContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    OrbitleLogoTile(size: 76)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: content.entry == .login ? "lock.fill" : "hourglass")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.orbitleOnAccent)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.orbitleAccent))
                                .overlay(Circle().strokeBorder(Color.orbitleBackground, lineWidth: 2.5))
                                .offset(x: 6, y: 6)
                        }
                        .padding(.top, 28)
                        .accessibilityHidden(true)
                    Text(content.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                        .accessibilityAddTraits(.isHeader)
                    Text(content.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(content.items, id: \.self) { item in
                            limit(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
            }
            // Кнопка вне прокрутки: длинный текст регистрации не уезжает под неё.
            Button {
                dismiss()
            } label: {
                Text("Понятно")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .orbitleProminentButtonStyle()
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .tint(Color.orbitleAccent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func limit(_ item: AccountLimitsContent.Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Self.symbol(item.icon))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func symbol(_ icon: AccountLimitsContent.Icon) -> String {
        switch icon {
        case .password: "key.fill"
        case .sessions: "laptopcomputer.and.iphone"
        case .messages: "bubble.left.fill"
        case .groups: "person.2.fill"
        case .other: "clock.fill"
        }
    }
}
