import SwiftUI
import PhotosUI
import UIKit
import OrbitlePresentation
import OrbitleUI

/// Регистрация нового номера: необязательное фото, имя и фамилия.
struct AuthRegistrationStep: View {
    @Bindable var viewModel: AuthViewModel

    private enum Field: Hashable {
        case firstName, lastName
    }

    @FocusState private var focus: Field?
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Image?

    var body: some View {
        AuthStepScroll {
            photoPicker
            AuthHeader(
                title: "Ваше имя",
                subtitle: Text("Укажите имя и, если хотите, фото. Их увидят собеседники.")
            )
            .padding(.top, 20)
            VStack(spacing: 0) {
                AuthFieldRow(showsTopDivider: true) {
                    TextField("Имя", text: $viewModel.firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focus = .lastName }
                }
                AuthFieldRow {
                    TextField("Фамилия (необязательно)", text: $viewModel.lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .lastName)
                        .submitLabel(.done)
                        .onSubmit { Task { await viewModel.register() } }
                }
            }
            .padding(.top, 28)
            AuthPrimaryButton(
                title: "Продолжить",
                isEnabled: viewModel.canRegister,
                isBusy: viewModel.isBusy
            ) {
                await viewModel.register()
            }
            .padding(.top, 24)
            AuthMessage(error: viewModel.errorMessage)
        }
        .onAppear {
            focus = .firstName
            photo = viewModel.registrationPhoto.flatMap(Self.image(from:))
        }
        .onChange(of: photoItem) { _, item in
            Task { await load(item) }
        }
    }

    private var photoPicker: some View {
        // Замыкание подписи PhotosPicker не привязано к главному актору, поэтому
        // подпись собирается заранее.
        let label = VStack(spacing: 10) {
            avatar
            Text(photo == nil ? "Добавить фото" : "Изменить фото")
                .font(.body)
                .foregroundStyle(.tint)
        }
        return PhotosPicker(selection: $photoItem, matching: .images) {
            label
        }
        .buttonStyle(.plain)
        .contextMenu {
            if photo != nil {
                Button("Удалить фото", systemImage: "trash", role: .destructive) {
                    photoItem = nil
                    photo = nil
                    viewModel.registrationPhoto = nil
                }
            }
        }
        .accessibilityLabel(Text(photo == nil ? "Добавить фото" : "Изменить фото"))
        .accessibilityHint(Text("Необязательно"))
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photo {
                    photo
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.fill.tertiary)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())

            if photo == nil {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .tint)
                    .background(Circle().fill(Color.orbitleBackground).padding(-2))
                    .offset(x: -2, y: -2)
            }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        viewModel.registrationPhoto = data
        photo = Self.image(from: data)
    }

    /// Миниатюра вместо полного снимка: в кружке 100 pt большего не нужно.
    private static func image(from data: Data) -> Image? {
        guard let full = UIImage(data: data) else { return nil }
        let side = 300.0
        let thumbnail = full.preparingThumbnail(of: CGSize(width: side, height: side * full.size.height / max(full.size.width, 1))) ?? full
        return Image(uiImage: thumbnail)
    }
}

/// Облачный пароль (2FA) в том же виде, что и остальные шаги.
struct AuthPasswordStep: View {
    @Bindable var viewModel: AuthViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        AuthStepScroll {
            AuthWordmark()
            AuthHeader(title: "Пароль", subtitle: Text(viewModel.passwordPrompt))
            AuthFieldRow(showsTopDivider: true) {
                SecureField("Пароль", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($isFocused)
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.submitPassword() } }
            }
            .padding(.top, 28)
            AuthPrimaryButton(
                title: "Продолжить",
                isEnabled: viewModel.canSubmitPassword,
                isBusy: viewModel.isBusy
            ) {
                await viewModel.submitPassword()
            }
            .padding(.top, 24)
            AuthMessage(error: viewModel.errorMessage)
        }
        .onAppear { isFocused = true }
    }
}
