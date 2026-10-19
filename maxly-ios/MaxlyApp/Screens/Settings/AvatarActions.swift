import SwiftUI
import PhotosUI
import UIKit
import MaxlyDomain
import MaxlyPresentation
import MaxlyUI

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
                     : "Разрешите Maxly доступ к камере в Настройках, чтобы сделать снимок.")
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

/// Своё фото на весь экран. Сразу видна картинка аватара из кэша, потом её сменяет оригинал;
/// щипок и двойное касание увеличивают, смахивание вверх или вниз закрывает. Справа —
/// «Поделиться» и меню: сохранить в «Фото» или «Файлы», изменить, удалить.
struct AvatarViewer: View {
    let account: AccountSettingsModel
    /// Размер аватара в шапке настроек: по нему находится картинка в кэше.
    var avatarSize: CGFloat = 96
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.imageURLSizing) private var imageURLSizing
    @State private var saver = ProfilePhotoSaver()
    @State private var confirmDelete = false
    @State private var zoomed = false
    @State private var chromeVisible = true
    @State private var dragOffset: CGFloat = 0
    @State private var dragging = false

    init(account: AccountSettingsModel, avatarSize: CGFloat = 96, onChange: @escaping () -> Void) {
        self.account = account
        self.avatarSize = avatarSize
        self.onChange = onChange
    }

    /// По порядку: оригинал, потом размеры сервера.
    private var candidates: [URL] { account.profile?.photoCandidates ?? [] }
    private var fullURL: URL? { candidates.first }

    /// Маленькая картинка шапки: тот же адрес и размер декодирования, что у `ProfileAvatar`.
    private var placeholder: UIImage? {
        let small = ImageURLRequests.url(
            account.profile?.avatarURL, shape: .square, pointSize: avatarSize, scale: displayScale,
            fullScreen: false, sizing: imageURLSizing
        )
        guard let small else { return nil }
        return ImagePipeline.shared.cached(small, maxPixel: Int(avatarSize * 3))?.image
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .opacity(MediaDismissRule.backgroundOpacity(offset: dragOffset, height: geo.size.height))
                    .ignoresSafeArea()
                PhotoPage(url: fullURL, fallbacks: Array(candidates.dropFirst()), placeholder: placeholder, turns: 0, onTap: {
                    withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
                }) { zoomed = $0 }
                .id(fullURL)
                .offset(y: dragOffset)
                .ignoresSafeArea()
                .accessibilityLabel("Фото профиля")
                if chromeVisible && dragOffset == 0 {
                    VStack {
                        header
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .simultaneousGesture(dismissDrag(height: geo.size.height))
        }
        .overlay(alignment: .bottom) { noticeView }
        .animation(.easeInOut(duration: 0.2), value: saver.notice)
        .statusBarHidden(!chromeVisible)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .profilePhotoExport(saver)
        .confirmationDialog("Удалить фото профиля?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить фото", role: .destructive) {
                Task {
                    await account.removePhoto()
                    if !account.hasPhoto { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// Слева «Закрыть», справа одна стеклянная капсула: «Поделиться» и «Ещё».
    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.app(.body, .semibold))
                    .foregroundStyle(.white)
                    .maxlyGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть")
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                Button {
                    saver.save(candidates, title: account.profile?.displayName ?? "", to: .share)
                } label: {
                    ZStack {
                        if saver.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(saver.isSaving || fullURL == nil)
                .accessibilityLabel("Поделиться")
                moreMenu
            }
            .font(.app(.body, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 2)
            .maxlyGlassCapsule(interactive: false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var moreMenu: some View {
        Menu {
            if fullURL != nil {
                Button("Сохранить в Фото", systemImage: "square.and.arrow.down") {
                    saver.save(candidates, title: account.profile?.displayName ?? "", to: .photos)
                }
                Button("Сохранить в Файлы", systemImage: "folder") {
                    saver.save(candidates, title: account.profile?.displayName ?? "", to: .files)
                }
            }
            Button("Изменить фото", systemImage: "photo.badge.plus") {
                dismiss()
                onChange()
            }
            Button("Удалить фото", systemImage: "trash", role: .destructive) {
                confirmDelete = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(saver.isSaving)
        .accessibilityLabel("Действия с фото")
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = saver.notice {
            Text(notice)
                .font(.app(.subheadline, .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 40)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }

    /// Смахивание вверх или вниз: фото идёт за пальцем, далеко или броском — закрыть.
    private func dismissDrag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard !zoomed else { return }
                if !dragging {
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    dragging = true
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                defer { dragging = false }
                guard dragging else { return }
                if MediaDismissRule.shouldClose(offset: dragOffset, velocity: value.velocity.height, height: height) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }
}
