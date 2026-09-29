import SwiftUI
import OrbitleUI

/// Выезжающая панель после входа на новом устройстве.
///
/// Сервер Max не даёт свежему сеансу завершать другие сеансы и менять облачный пароль:
/// так он защищает аккаунт, если вход выполнил кто-то чужой. Отдельного признака в ответе
/// сервера нет, поэтому панель показывается после каждого входа по коду.
struct NewSessionNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            OrbitleLogoTile(size: 76)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.orbitleAccent))
                        .overlay(Circle().strokeBorder(Color.orbitleBackground, lineWidth: 2.5))
                        .offset(x: 6, y: 6)
                }
                .padding(.top, 28)
                .accessibilityHidden(true)
            Text("Новый сеанс")
                .font(.title2.bold())
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text("Вы вошли в Max на этом устройстве. Пока сеанс новый, часть настроек безопасности недоступна.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 14) {
                limit(
                    systemImage: "rectangle.portrait.and.arrow.right",
                    title: "Нельзя завершать другие сеансы",
                    detail: "Выйти на других устройствах можно будет позже или с устройства, где вход выполнен давно."
                )
                limit(
                    systemImage: "key.fill",
                    title: "Нельзя менять облачный пароль",
                    detail: "Смена и отключение пароля станут доступны, когда сеанс перестанет быть новым."
                )
            }
            .padding(.top, 22)
            Spacer(minLength: 20)
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
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .tint(Color.orbitleAccent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func limit(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
