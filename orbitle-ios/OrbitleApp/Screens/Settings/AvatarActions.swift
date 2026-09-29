import SwiftUI
import PhotosUI
import UIKit
import OrbitlePresentation
import OrbitleUI

/// Выбор нового фото профиля: «Загрузить из галереи», «Сделать снимок», «Отмена».
/// Снимок идёт через системную камеру с запросом доступа, фото — через `PhotosPicker`.
struct AvatarPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let account: AccountSettingsModel
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var cameraProblem: CameraAccess.Result?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Фото профиля", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Загрузить из галереи") { showsLibrary = true }
                Button("Сделать снимок") {
                    Task {
                        let access = await CameraAccess.request()
                        if access == .granted { showsCamera = true } else { cameraProblem = access }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .photosPicker(isPresented: $showsLibrary, selection: $libraryItem, matching: .images, preferredItemEncoding: .compatible)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = AvatarJPEG.make(from: data) else {
                        account.errorMessage = "Не удалось прочитать фото"
                        return
                    }
                    await account.uploadPhoto(jpeg: jpeg)
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    guard let jpeg = AvatarJPEG.make(from: image) else { return }
                    Task { await account.uploadPhoto(jpeg: jpeg) }
                }
                .ignoresSafeArea()
            }
            .alert(
                cameraProblem == .unavailable ? "Камера недоступна" : "Нет доступа к камере",
                isPresented: Binding(get: { cameraProblem != nil }, set: { if !$0 { cameraProblem = nil } })
            ) {
                if cameraProblem == .denied {
                    Button("Открыть настройки") { CameraAccess.openSettings() }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(cameraProblem == .unavailable
                     ? "На этом устройстве нет камеры."
                     : "Разрешите Orbitle доступ к камере в Настройках, чтобы сделать снимок.")
            }
    }
}

extension View {
    func avatarPicker(isPresented: Binding<Bool>, account: AccountSettingsModel) -> some View {
        modifier(AvatarPickerModifier(isPresented: isPresented, account: account))
    }
}

/// Аватар профиля в круге: фото с сервера или инициалы. Во время загрузки — индикатор поверх.
struct ProfileAvatar: View {
    let account: AccountSettingsModel
    var size: CGFloat = 96

    var body: some View {
        AvatarView(
            title: account.profile?.displayName ?? "Я",
            id: account.profile?.id,
            url: account.profile?.avatarURL,
            size: size
        )
        .overlay {
            if account.isUpdatingPhoto {
                Circle().fill(.black.opacity(0.35))
                ProgressView().tint(.white)
            }
        }
    }
}

/// Просмотр своего фото на весь экран с меню: сохранить, поделиться, изменить, удалить.
struct AvatarViewer: View {
    let account: AccountSettingsModel
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmDelete = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Фото профиля")
                } else {
                    ProgressView().tint(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let image {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                saved = true
                            } label: {
                                Label("Сохранить в Фото", systemImage: "square.and.arrow.down")
                            }
                            let shared = Image(uiImage: image)
                            ShareLink(item: shared, preview: SharePreview("Фото профиля", image: shared)) {
                                Label("Поделиться", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            dismiss()
                            onChange()
                        } label: {
                            Label("Изменить фото", systemImage: "photo.badge.plus")
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Удалить фото", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Действия с фото")
                }
            }
            .confirmationDialog("Удалить фото профиля?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить фото", role: .destructive) {
                    Task {
                        await account.removePhoto()
                        if !account.hasPhoto { dismiss() }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Фото сохранено", isPresented: $saved) {
                Button("OK", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .task(id: account.profile?.avatarURL) {
            guard let url = account.profile?.avatarURL else { return }
            image = await ImagePipeline.shared.image(for: url)?.image
        }
    }
}
